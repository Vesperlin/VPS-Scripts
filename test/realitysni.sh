#!/usr/bin/env bash

TEST_TIMES=10
TIMEOUT_SEC=2

DOMAINS=(
www.tesla.com
api.company-target.com
lpcdn.lpsnmedia.net
gray-config-prod.api.cdn.arcpublishing.com
c.s-microsoft.com
www.xbox.com
amd.com
d1.awsstatic.com
xp.apple.com
aws.com
statici.icloud.com
ts4.tc.mm.bing.net
github.gallerycdn.vsassets.io
ms-python.gallerycdn.vsassets.io
res-1.cdn.office.net
th.bing.com
i7158c100-ds-aksb-a.akamaihd.net
download.amd.com
fpinit.itunes.apple.com
drivers.amd.com
)

YELLOW=$'\e[33m'
GREEN=$'\e[32m'
BOLD=$'\e[1m'
RESET=$'\e[0m'

RESULT_FILE=$(mktemp)

for d in "${DOMAINS[@]}"; do
  echo "测试 $d"

  times=()
  sum=0
  success=0

  for ((i=1;i<=TEST_TIMES;i++)); do
    start=$(date +%s%3N)
    if timeout ${TIMEOUT_SEC}s openssl s_client \
      -connect "$d:443" \
      -servername "$d" \
      </dev/null &>/dev/null
    then
      end=$(date +%s%3N)
      cost=$((end - start))
      times+=("$cost")
      sum=$((sum + cost))
      success=$((success + 1))
    else
      times+=("timeout")
    fi
    echo "第 $i 次测试完成"
    sleep 0.2
  done

  if [[ $success -gt 0 ]]; then
    avg=$((sum / success))
  else
    avg=99999
  fi

  echo "$avg|$d|${times[*]}" >> "$RESULT_FILE"
  echo
done

rank=1
sort -n "$RESULT_FILE" | while IFS="|" read -r avg domain times; do
  if [[ $rank -le 3 ]]; then
    NAME_STYLE="${BOLD}${YELLOW}"
  else
    NAME_STYLE="${YELLOW}"
  fi

  printf "%s%02d) %-45s %s%4dms%s%s\n" \
    "$NAME_STYLE" "$rank" "$domain" \
    "$GREEN" "$avg" "$RESET" "$RESET"

  echo "$times"
  echo

  rank=$((rank + 1))
done

rm -f "$RESULT_FILE"
