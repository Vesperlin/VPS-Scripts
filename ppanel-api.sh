#!/usr/bin/env bash
#=================｜基础环境｜=======================      
export DEBIAN_FRONTEND=noninteractive

LOG="/root/init.log"
exec 1>>"$LOG" 2> >(tee -a "$LOG" >&2)

#====================｜函数｜======================      
#----------------------log---------------------------
log() {
  echo "$@" >&2
}
#-------------progress_bar_task--------------------
progress_bar_task() {
  local pid="$1"
  local label="$2"
  local width=40
  local percent=0

  while kill -0 "$pid" 2>/dev/null; do
    percent=$((percent + 1))
    ((percent > 99)) && percent=99

    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    printf "\r\033[K" >&2

    printf "[%s] [" "$label" >&2
    printf "\033[42m%${filled}s\033[0m" "" | tr ' ' ' ' >&2
    printf "%${empty}s" "" >&2
    printf "] %3d%%" "$percent" >&2

    sleep 0.2
  done

  # 结束时补满 + 换行
  printf "\r\033[K[%s] [" "$label" >&2
  printf "\033[42m%${width}s\033[0m" "" | tr ' ' ' ' >&2
  printf "] 100%%\n" >&2
}
#----------------------彩色文字-----------------------
cecho() {
  local color="$1"
  local style="$2"
  local text

  if [[ $# -eq 2 ]]; then
    text="$2"
    style=""
  else
    text="$3"
  fi

  local code=""

  case "$color" in
    black)   code="30" ;;
    red)     code="31" ;;
    green)   code="32" ;;
    yellow)  code="33" ;;
    blue)    code="34" ;;
    purple)  code="35" ;;
    cyan)    code="36" ;;
    white)   code="37" ;;
    *)       code="0"  ;;
  esac

  case "$style" in
    bold)    code="1;${code}" ;;
    dim)     code="2;${code}" ;;
    underline) code="4;${code}" ;;
  esac

  printf "\033[%sm%s\033[0m\n" "$code" "$text" >&2
}
#---------------------retry-----------------------
retry() {
  local max=3
  local n=0

  until "$@"; do
    ((n++))
    if [[ $n -ge $max ]]; then
      cecho red bold "[FAIL] $*（已重试 $n 次）"
      return 1
    fi
    cecho yellow "[RETRY] $*（第 $n 次）"
    sleep 2
  done
}


#------------------------apt_run-------------------
apt_run() {
  local msg="$1"
  shift
  apt -o Dpkg::Progress-Fancy="0" "$@" >/dev/null 2>&1 &
  local pid=$!
  
  progress_bar_task "$pid" "$msg"
  wait "$pid"
}


cecho blue bold "===== PPanel-docker后端部署 ====="
cecho green  "api后端域名SSL证书配置 "
cecho white  "请确保DNS已正确指向此服务器，且已申请了SSL证书 "
read -p "请输入后端api域名 >" apidomain && export apidomain
read -p "[1]SSL证书路径 -- [直接回车]粘贴SSL证书内容>" SSLchoice && export SSLchoice ||SSLchoice=$2 && export SSLchoice
if test $SSLchoice = "1"; then
   cecho yellow "下面请正确输入证书路径"
   read -p "源文件路径>" fullchain && export fullchain
   read -p "密钥路径>" privkey && export privkey
else
   read -p "[1]单证书 -- [直接回车]通配符证书> " SSLchoices && export SSLchoices ||SSLchoices=$2 && export SSLchoices
   if test $SSLchoices = "1"; then
      read -p "请输入通配符主域>" SSLdomain && export SSLdomain
   else
      SSLdomain=$apidomain && export SSLdomain
   fi
   read -p "请粘贴源文件内容（.pem）>" fullchaintext && export fullchaintext
   read -p "请粘贴密钥内容（.pem）>" privkeytext && export privkeytext
fi
cecho green  "请输入MySQL数据库密码 "
read -p "直接回车默认随机生成 >" MYSQLpassword && export MYSQLpassword ||apt install -y uuid-runtime >/dev/null 2>&1 && MYSQLpassword=$(uuidgen) && export MYSQLpassword
cecho green  "请输入JWT密码 "
read -p "直接回车默认随机生成 >" JWTpassword && export JWTpassword ||apt install -y uuid-runtime >/dev/null 2>&1 && JWTpassword=$(uuidgen) && export JWTpassword
bash https://raw.githubusercontent.com/Vesperlin/VPS-Scripts/refs/heads/main/init/ppanel-api.sh /dev/null 2>&1


