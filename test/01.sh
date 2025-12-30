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

#------------------------------------------------
pause() {
  cecho white
  cecho white -rp "请选择要执行的操作："
}

error_msg() {
  cecho white
  cecho  red "未输入有效数字"
  sleep 1
}

# ========= 菜单展示 =========


# ========= 具体动作 =========
do_action() {
  case "$1" in
    1)
      cecho white ">>>  磁盘读写测试"
      dd if=/dev/zero of=test bs=64k count=4k oflag=dsync
      ;;
    2)
      cecho white ">>>  带宽 IO CPU 一键测试"
      wget -qO- bench.sh | bash
      ;;
    3)
      cecho white ">>>  查看系统数据"
      apt install neofetch -y >/dev/null 2>&1 && neofetch
      ;;
    4)
      cecho white ">>>  硬件测试"
      wget -q https://github.com/Aniverse/A/raw/i/a>/dev/null 2>&1 && bash a                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               
      bash <(curl -L -s check.unlock.media)
      ;;
    6)
      cecho white ">>>  三网回程线路质量"
      curl https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh -sSf | sh    
      ;;
    7)
      cecho white "全球速度测试"
      wget -qO- nws.sh | bash
      ;;
    8)
      cecho white ">>>  IP质量"
      bash <(curl -sL IP.Check.Place)
      ;;
    9)
      cecho white ">>>  流媒体测试"
      curl bash <(wget -qO- https://down.vpsaff.net/linux/speedtest/superbench.sh) -m  
      ;;
    10)
      cecho white ">>>  三网回程详细"
      wget -qO- git.io/besttrace | bash
      rm /usr/local/bin/nexttrace
      ;;
    11)
      cecho white ">>>  三网回程线路质量"
      curl https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh -sSf | sh
      ;;
    12)
      cecho white ">>>  四网路由"
      curl https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh -sSf | sh                                                                                                                                                                                                                                                                                                        
      ;;
      
  esac
}

# ========= 主循环 =========
while true; do
  clear
  cecho white "Vesper 管理面板"
  cecho white "------------------------------------------------"
  cecho white"0. 回到上一层"
  cecho white "------------------------------------------------"
  cecho white "1. 磁盘读写测试"
  cecho white "2. 带宽 IO CPU 一键测试"
  cecho white "3. 查看系统数据"
  cecho white "4. 硬件测试"
  cecho white "5. 流媒体解锁测试"
  cecho white "6. 三网回程线路质量"
  cecho white "7. 全球速度测试"
  cecho white "8. IP质量"
  cecho white "9. 流媒体测试"
  cecho white "10. 三网回程详细"
  cecho white "11. 三网回程线路质量"
  cecho white"12. 四网路由"
------------------------------------------------"

  read -rp "请选择要执行的操作：" choice

  # 空输入
  [[ -z "$choice" ]] && error_msg && continue

  # 非数字
  [[ ! "$choice" =~ ^[0-9]+$ ]] && error_msg && continue

  # 越界
  (( choice < 0 || choice > 12 )) && error_msg && continue

  # 退出
  if [[ "$choice" == "0" ]]; then
    cecho yellow "Bye."
    exit 0
  fi

  # 执行动作
  do_action "$choice"
  pause
done
