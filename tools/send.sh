#!/bin/bash
# This script sends a message of up to 127 bytes to a websocket server.
# modified from https://github.com/VeryBueno/bash-websocket-client/blob/master/websocket_echo_example.sh

# generate a random Sec-WebSocket-Key
random_bytes="$(dd if=/dev/urandom bs=16 count=1 2> /dev/null)"
HS_KEY=`echo "$random_bytes" | base64`

# The header values to use when performing a websocket handshake.
HS_GET="/?encoding=text"
HS_ORIGIN="http://www.websocket.org"
HS_HOST="echo.websocket.org"

handshake="\
GET $HS_GET HTTP/1.1\r
Origin: $HS_ORIGIN\r
Connection: Upgrade\r
Host: $HS_HOST\r
Sec-WebSocket-Key: $HS_KEY\r
Upgrade: websocket\r
Sec-WebSocket-Version: 13\r\n\r\n"

function dec_to_hex {
   printf "%02x" $1
}

# translate a char or byte to an int
function ord {
   echo -n "$1" | hexdump -v -e "\"%d\""
}

# mask a message ($1) with a masking key ($2).
function mask_msg {
   msg=$1; msg_len=${#msg}
   mk=$2; mk_len=${#mk}

   masked=""

   for (( i=0; i<$msg_len; i++ ))
   do
      mk_i=`expr $i % $mk_len`

      msg_chr=${msg:$i:1}
      mk_chr=${mk:$mk_i:1}

      msg_int=`ord "$msg_chr"`
      mk_int=`ord "$mk_chr"`

      let "msg_int ^= $mk_int"

      chr_val="\x`dec_to_hex $msg_int`"
      masked+=$chr_val
   done
   echo -n -e $masked
}

# generate the opcode and message length for the message
function make_header {
   msg_size=${#1}
   first_byte="\x81"
   second_byte=128
   let "second_byte ^= $msg_size"
   second_byte=$(dec_to_hex $second_byte)
   echo -n -e "$first_byte\x$second_byte"
}

# message to send
msg="$1"

# generate a random 4-byte masking key
masking_key="$(dd if=/dev/urandom bs=4 count=1 2> /dev/null)"

# generate the header and mask the message
header=$(make_header "$msg")
masked_msg=$(mask_msg "$msg" "$masking_key")
to_send="$header$masking_key$masked_msg"

trap "echo sigterm >&2;exit" TERM
echo -ne "$handshake"
echo "Sending handshake" >&2

while read -r -t 1 line
do
   echo $line >&2
   if [[ $line == Sec-WebSocket-Accept* ]]; then
     echo "Handshake accepted" >&2
     break
   fi
done

echo -ne "$to_send"
echo "Sending payload $2" >&2

cat <&0 >&2 & 
sleep 2; kill $!

#line=""
#while read -r -d "" -t 1 -n1 byte
#do
#   line=${line}${byte}
#   if [ "${byte}" == "\n" ]; then
#     echo Line: $line >&2
#     line=""
#   fi
#done
#echo Last line: $line >&2

echo >&2
echo "Done" >&2
