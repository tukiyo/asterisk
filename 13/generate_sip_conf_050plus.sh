#!/bin/sh
set -eu

## key, pub
TLSCAFILE=$(find /etc/asterisk/ -type f -name "*.key")
TLSCERTFILE=$(find /etc/asterisk/ -type f -name "*.pub")
if [ -z $TLSCAFILE -o -z $TLSCERTFILE ];then
    echo "[quit] /etc/asterisk/*.{key,pub}が見つかりません。"
    echo "astgenkeyコマンドで生成してください。"
    exit 1
fi

## [050plusからasterisk用の接続情報を取得する用]
# 050電話番号
echo -n "(1/3) Enter 050plus tel number : "
read TEL
# 050plusのパスワード
echo -n "(2/3) Enter 050plus tel password : "
stty -echo
read PASS
stty echo

# -------------

get_xml() {
  set -eux
  wget -q \
    -O ${TEL}.xml \
    --no-check-certificate \
    --secure-protocol=auto \
    --server-response \
    --post-data \
    "ifVer=2.0&apVer=2.0.4&buildOS=IOS&buildModel=iPhone4,1&buildVer=5.1&no050=${TEL}&pw050=${PASS}" \
    "https://start.050plus.com/sFMCWeb/other/InitSet.aspx"
  set +x
}

get_config() {
  sed -e 's@<@\n<@g' ${TEL}.xml | grep "<${1}>" | cut -f 2 -d ">"
}

## [main]
if [ ! -r ${TEL}.xml ];then
    get_xml
fi
nicNm=`get_config nicNm`
sipPwd=`get_config sipPwd`
sipID=`get_config sipID`
tranGwAd=`get_config tranGwAd`
freeTranGwPNm=`get_config freeTranGwPNm`
# -------------

## asteriskで待ち受けるポート番号
echo
echo -n "(3/3) Enter Asterisk's listen port : "
read LISTEN_PORT

cat > sip.conf << EOF
[general]
context=default
port=${LISTEN_PORT}
bindaddr=0.0.0.0
;
maxexpirey=3600
defaultexpirey=3600
context=default
;TLS settings
tlsenable=yes
tlsbindaddr=0.0.0.0
tlscertfile="${TLSCERTFILE}"
tlscafile="${TLSCAFILE}"
tlscipher=ALL
tlsclientmethod=tlsv1
tlsdontverifyserver=yes ; TLSのサーバーのCommonNameの検証を無効にする
register => tls://${nicNm}:${sipPwd}:${sipID}@${tranGwAd}:${freeTranGwPNm}/200

[050plus]
type=friend
secret=${sipPwd}
port=${freeTranGwPNm}
defaultuser=${sipID}
fromuser=${nicNm}
;host=60.37.58.170
host=${tranGwAd}
fromdomain=050plus.com
context=default
insecure=invite,port
dtmfmode=inband
canreinvite=no
disallow=all
allow=ulaw
callgroup=1
transport=tls
encryption=yes
nat=yes 
EOF

echo '[done]'
echo '[info] sudo sh -c "cat sip.conf > /etc/asterisk/sip.conf"'
ls -lh sip.conf
