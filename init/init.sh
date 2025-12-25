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


cecho blue bold "===== VPS 初始开荒脚本 ====="
cecho blue  "作者：Vesper"


#===================｜系统更新｜======================
cecho blue bold "1.系统更新"
apt_run "获取资源" update
apt_run "更新" upgrade --only-upgrade -y
cecho green "   --完成"

#===================｜工具安装｜======================
cecho blue bold "2.安装常用工具"
TOOLS=(
  curl
  wget
  git
  vim
  tzdata
  htop
  build-essential
  zip
  tree 
  net-tools
  unzip
  tmux
  command-not-found
  python3-pip
  openvpn
  neofetch
  jq
  trash-cli
  inetutils-traceroute
)

for pkg in "${TOOLS[@]}"; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    cecho cyan "   --$pkg 已安装"
    continue
  fi

apt -o Dpkg::Progress-Fancy="0" install -y "$pkg" >/dev/null 2>&1 &
pid=$!
progress_bar_task "$pid" "install $pkg"
wait "$pid"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    cecho green "  --$pkg 已安装"
  else
    cecho yellow "     --$pkg 安装失败"
    apt_run "尝试修复" --fix-broken install -y
    dpkg --configure -a >/dev/null 2>&1
apt -o Dpkg::Progress-Fancy="0" install -y "$pkg" >/dev/null 2>&1 &
pid=$!
progress_bar_task "$pid" "install $pkg"
wait "$pid"

    dpkg -s "$pkg" >/dev/null 2>&1 \
      && cecho green "  --$pkg 已安装" \
      || cecho red "  --$pkg 放弃安装 "
  fi
done

#===================｜vim默认｜======================

cecho blue bold "3.设置默认编辑器为 vim"

update-alternatives --set editor /usr/bin/vim.basic >/dev/null 2>&1 && \
  cecho green "   --成功" || \
  cecho red "   --vim设置失败"

#=================｜自动安全更新｜=====================
cecho blue bold "4.设置自动安全更新"
DEBIAN_FRONTEND=noninteractive apt install -y unattended-upgrades \
  >/dev/null 2>&1
printf "\n" >&2
dpkg-reconfigure --priority=low unattended-upgrades \
  >/dev/null 2>&1 && \
  cecho green "   --成功" || \
  cecho yellow "   --启用失败"

#===================｜创建用户｜======================
cecho blue bold "5.创建用户 vesper"
if id vesper >/dev/null 2>&1; then
  cecho white "   --用户 vesper 已存在"
else
  adduser --disabled-password --gecos "" vesper >/dev/null 2>&1 && \
  echo "vesper:Cici080306" | chpasswd || \
  cecho red "   -- 创建失败"
fi
usermod -aG sudo vesper >/dev/null 2>&1 || \
  cecho red "   --授予权限失败"
echo "vesper ALL=(ALL) ALL" >/etc/sudoers.d/vesper
chmod 440 /etc/sudoers.d/vesper && \
  cecho green "   --成功" || \
  cecho red "   --权限文件修改失败"


#================｜修改配置｜====================
cecho blue bold "6.延长ssh断联时间" 
cat > /etc/ssh/sshd_config <<'EOF'
#---------------------/全局SSH服务器配置文件/--------------------------
# ·更多信息参阅 sshd_config(5）
# ·此sshd服务器使用 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games 环境变量编译
# ·OpenSSH 默认附带的 sshd_config 配置文件采用以下策略：
#        -尽可能使用默认值指定选项，但保留注释状态。
#        -取消注释的选项将覆盖默认值。
#-------------------------------------------------------------------
Include /etc/ssh/sshd_config.d/*.conf
#-------------------------------------------------------------------
Port 36222
#-------------------------------------------------------------------
#【客户端活动间隔】
ClientAliveInterval 60
#【客户端活动次数上限】
ClientAliveCountMax 999
#【TCP保持活动】
TCPKeepAlive yes
#【使用DNS】
UseDNS no
#【允许代理转发】
AllowAgentForwarding yes
#【允许TCP转发】
AllowTcpForwarding yes
#【使用PAM】
UsePAM yes
#【禁用X11转发】
X11Forwarding no
#-------------------------------------------------------------------
GatewayPorts no
PrintMotd no
#-------------------------------------------------------------------
#AddressFamily any
#ListenAddress 0.0.0.0
#ListenAddress ::
#-------------------------------------------------------------------
#HostKey /etc/ssh/ssh_host_rsa_key
#HostKey /etc/ssh/ssh_host_ecdsa_key
#HostKey /etc/ssh/ssh_host_ed25519_key
#-------------------------------------------------------------------
# /默认重置密钥限制/
#RekeyLimit default none
# /系统日志功能/
#SyslogFacility AUTH
# /日志级别/
#LogLevel INFO
#-------------------------------------------------------------------
# /登录宽限时间/
#LoginGraceTime 2m
#【允许根用户登录】
PermitRootLogin yes
# /严格模式/
#StrictModes yes
# /最大认证尝试次数/
#MaxAuthTries 8
# /最大会话数/
#MaxSessions20
#-------------------------------------------------------------------
# /预计未来默认情况下将忽略 .ssh/authorized_keys2 文件/
#AuthorizedKeysFile	.ssh/authorized_keys .ssh/authorized_keys2
#AuthorizedPrincipalsFile none
#AuthorizedKeysCommand none
#AuthorizedKeysCommandUser nobody
#-------------------------------------------------------------------
# /使其生效 还需在 /etc/ssh/ssh_known_hosts 中添加主机密钥/
#HostbasedAuthentication no
# /若不信任 ~/.ssh/known_hosts 文件，请将其改为 yes 主机基于身份验证/
#IgnoreUserKnownHosts no
# /不要读取用户的 ~/.rhosts 和 ~/.shosts 文件/
#IgnoreRhosts yes
# /禁用隧道传输的明文密码/
#PermitEmptyPasswords no
#【挑战响应密码】
KbdInteractiveAuthentication no
#-------------------------------------------------------------------
# /Kerberos身份验证/
#KerberosAuthentication no
# /Kerberos或本地密码/
#KerberosOrLocalPasswd yes
# /Kerberos票证清理/
#KerberosTicketCleanup yes
# /Kerberos获取AFS令牌/
#KerberosGetAFSToken no
#-------------------------------------------------------------------
# /GSSAPI身份验证/
#GSSAPIAuthentication no
# /GSSAPI清理凭据/
#GSSAPICleanupCredentials yes
# /GSSAPI严格接受方检查/
#GSSAPIStrictAcceptorCheck yes
# /GSSAPI密钥交换/
#GSSAPIKeyExchange no
#-------------------------------------------------------------------
#X11DisplayOffset 10
#X11UseLocalhost yes
#PermitTTY yes
#PrintLastLog yes
#PermitUserEnvironment no
#Compression delayed
#PidFile /run/sshd.pid
#MaxStartups 10:30:100
#PermitTunnel no
#ChrootDirectory none
#VersionAddendum none
# /无默认横幅路径/
#Banner none
#-------------------------------------------------------------------
#【允许客户端传递区域设置环境变量】
AcceptEnv LANG LC_*
#【覆盖默认的无子系统设置】
Subsystem	sftp	/usr/lib/openssh/sftp-server
#-------------------------------------------------------------------
# /按用户覆盖设置的示例/
#Match User anoncvs
#	X11Forwarding no
#	AllowTcpForwarding no
#	PermitTTY no
#	ForceCommand cvs server
#-------------------------------------------------------------------
PasswordAuthentication yes
PubkeyAuthentication no
#-------------------------------------------------------------------

EOF
cecho green "   --成功"
cecho yellow "   --SSH 端口已修改为36222"
#==================｜关闭欢迎语｜=====================
cecho blue bold "7.关闭 SSH 登录欢迎语"
sed -i 's/^session\s\+optional\s\+pam_motd.so/#&/' /etc/pam.d/sshd
sed -i 's/^session\s\+optional\s\+pam_motd.so/#&/' /etc/pam.d/login
sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news
cecho green "   --成功"
#================｜修改颜色｜====================
cp /home/vesper/.bashrc /root/.bashrc || true
cecho blue "8.修改颜色"
cat > /home/vesper/.bashrc <<'EOF'
#----------------------------------------------------------------------
#           ~/.bashrc
# ·由bash(1)在非登录shell中执行。
# ·示例请参见/usr/share/doc/bash/examples/startup-files（位于bash-doc软件包中）
# ·若非交互式运行，则不执行任何操作
#----------------------------------------------------------------------
case $- in
    *i*) ;;
      *) return;;
esac
#----------------------------------------------------------------------
# /历史中不保留重复行或以空格开头的行/
HISTCONTROL=ignoreboth

# /追加到历史记录文件，不要覆盖它/
shopt -s histappend

# /设置历史记录长度/
HISTSIZE=1000
HISTFILESIZE=2000
#----------------------------------------------------------------------
# /在每次命令执行后检查窗口尺寸，并在必要时更新 LINES 和 COLUMNS 的值/
shopt -s checkwinsize
#----------------------------------------------------------------------
# /若设置此选项，在路径名扩展上下文中使用的模式"**"将匹配所有文件以及零个或多个目录和子目录/
#shopt -s globstar
#----------------------------------------------------------------------
# /使less对非文本输入文件更友好/
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
#----------------------------------------------------------------------
# /设置标识工作 chroot 环境的变量/
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi
#----------------------------------------------------------------------
# /设置一个花哨的提示符（非彩色，除非我们确定需要彩色）/
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac
#----------------------------------------------------------------------
# /启用彩色提示符/
#   - 默认关闭以避免干扰用户
# /终端窗口的焦点应集中在命令输出而非提示符上/
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	 # /我们支持颜色功能,假设其符合 Ecma-48/(ISO/IEC-6429) 标准/
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;33m\]\u\[\033[00m\]:\[\033[01;31m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt
#----------------------------------------------------------------------

# /若此为xterm终端，则将标题设置为用户@主机:目录/
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac
#----------------------------------------------------------------------
# /启用 ls 命令的颜色支持，并添加实用别名/
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi
#----------------------------------------------------------------------
# /带颜色的GCC警告和错误/
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
#----------------------------------------------------------------------
# /更多 ls 别名/
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
#----------------------------------------------------------------------
# /为长时间运行的命令添加"alert"别名/
# 使用方式如下: sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
#----------------------------------------------------------------------
# /别名定义/
#   -建议将所有新增内容另存为独立文件
#   -如 ~/.bash_aliases,而非直接添加在此处

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi
#----------------------------------------------------------------------
# /启用可编程补全功能/
#   -若已在 /etc/bash.bashrc 和 /etc/profile 中启用，则无需重复启用
#   -执行 /etc/bash.bashrc 文件
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
#----------------------------------------------------------------------
# /pnpm/
export PNPM_HOME="/root/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
#----------------------------------------------------------------------
# /bun/
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
alias rm='trash-put'
alias php81='php81 -c /www/server/php/81/etc/php-cli.ini'
#----------------------------------------------------------------------

EOF

chown vesper:vesper /home/vesper/.bashrc

cat > /root/.bashrc <<'EOF'
#----------------------------------------------------------------------
#           ~/.bashrc
# ·由bash(1)在非登录shell中执行。
# ·示例请参见/usr/share/doc/bash/examples/startup-files（位于bash-doc软件包中）
# ·若非交互式运行，则不执行任何操作
#----------------------------------------------------------------------
case $- in
    *i*) ;;
      *) return;;
esac
#----------------------------------------------------------------------
# /历史中不保留重复行或以空格开头的行/
HISTCONTROL=ignoreboth

# /追加到历史记录文件，不要覆盖它/
shopt -s histappend

# /设置历史记录长度/
HISTSIZE=1000
HISTFILESIZE=2000
#----------------------------------------------------------------------
# /在每次命令执行后检查窗口尺寸，并在必要时更新 LINES 和 COLUMNS 的值/
shopt -s checkwinsize
#----------------------------------------------------------------------
# /若设置此选项，在路径名扩展上下文中使用的模式"**"将匹配所有文件以及零个或多个目录和子目录/
#shopt -s globstar
#----------------------------------------------------------------------
# /使less对非文本输入文件更友好/
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
#----------------------------------------------------------------------
# /设置标识工作 chroot 环境的变量/
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi
#----------------------------------------------------------------------
# /设置一个花哨的提示符（非彩色，除非我们确定需要彩色）/
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac
#----------------------------------------------------------------------
# /启用彩色提示符/
#   - 默认关闭以避免干扰用户
# /终端窗口的焦点应集中在命令输出而非提示符上/
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	 # /我们支持颜色功能,假设其符合 Ecma-48/(ISO/IEC-6429) 标准/
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;34m\]\u\[\033[00m\]:\[\033[01;35m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt
#----------------------------------------------------------------------

# /若此为xterm终端，则将标题设置为用户@主机:目录/
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac
#----------------------------------------------------------------------
# /启用 ls 命令的颜色支持，并添加实用别名/
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi
#----------------------------------------------------------------------
# /带颜色的GCC警告和错误/
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
#----------------------------------------------------------------------
# /更多 ls 别名/
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
#----------------------------------------------------------------------
# /为长时间运行的命令添加"alert"别名/
# 使用方式如下: sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
#----------------------------------------------------------------------
# /别名定义/
#   -建议将所有新增内容另存为独立文件
#   -如 ~/.bash_aliases,而非直接添加在此处

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi
#----------------------------------------------------------------------
# /启用可编程补全功能/
#   -若已在 /etc/bash.bashrc 和 /etc/profile 中启用，则无需重复启用
#   -执行 /etc/bash.bashrc 文件
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
#----------------------------------------------------------------------
# /pnpm/
export PNPM_HOME="/root/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
#----------------------------------------------------------------------
# /bun/
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
alias rm='trash-put'
alias php81='php81 -c /www/server/php/81/etc/php-cli.ini'
#----------------------------------------------------------------------
EOF
cecho green "   --成功"
#===================｜root密码｜======================
cecho blue bold "9.设置 root 密码"

echo "root:Cici080306" | chpasswd && \
  cecho yellow "   --密码 Cici080306" && \
  cecho green "   --成功"|| \
  cecho red "   --设置失败"

#===================｜Swap｜======================
cecho blue bold "10.创建Swap"
ENABLE_SWAP=1
SWAP_SIZE=2G

if [[ "$ENABLE_SWAP" == "1" ]]; then
  if swapon --show | grep -q swap; then
    cecho cyan "   --Swap 已存在 跳过"
  else
    fallocate -l "$SWAP_SIZE" /swapfile && \
    chmod 600 /swapfile && \
    mkswap /swapfile >/dev/null 2>&1 && \
    swapon /swapfile && \
    echo '/swapfile none swap sw 0 0' >> /etc/fstab && \
    cecho yellow "   --已启用 ($SWAP_SIZE)" && \
    cecho green "   --成功" || \
    cecho red "   --Swap 创建失败"
  fi
else
  cecho red "  --已按配置禁用 swap"
fi
#===================｜时区｜======================
cecho blue bold "11.修改系统时区｜上海 "
timedatectl set-timezone Asia/Shanghai >/dev/null 2>&1 && \
  cecho green "   --成功 " || \
  cecho red "   --设置失败"
#===================｜界面汉化｜======================
cecho blue bold "12.语言修改为中文 "
locale >/dev/null 2>&1
locale-gen zh_CN.UTF-8 >/dev/null 2>&1
update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 >/dev/null 2>&1
cat /etc/default/locale >/dev/null 2>&1
export LANG=zh_CN.UTF-8 >/dev/null 2>&1
export LC_ALL=zh_CN.UTF-8 >/dev/null 2>&1
apt_run "检查更新" update
apt_run "安装zh语言包" install -y language-pack-zh-hans
cecho green "   --成功 "
#===================｜清理｜======================
cecho blue bold "13.清理系统垃圾"
apt_run "apt autoremove" autoremove -y
apt autoclean -y >/dev/null 2>&1 && \
cecho green "   --成功"  || \
  cecho red "   --设置失败"

#===================｜清理｜======================
cecho white "--中文语言环境已配置 执行 exit ，重新连接ssh后即可生效
重连后您可使用 ls /not-exist 检查来检查是否配置成功 "

cecho white "如有任何问题可反馈至 shuhany86@gmail.com"
cecho purple "  -------感谢使用本脚本------"
cecho purple bold "===== VPS 初始开荒完成 ====="
