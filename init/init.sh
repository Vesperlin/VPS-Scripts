

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
  sudo
  curl
  vim
  wget
  git
  ca-certificates
  iproute2
  lsof
  jq
  unzip
  zip
  tree 
  htop
  trash-cli
  inetutils-traceroute
  bash-completion
  less
  psmisc
  cron
  file
  uuid-runtime
  whois
  tzdata
  gnupg
  unzip
  tmux
  lsb-release
  command-not-found
  dnsutils
  logrotate
  build-essential
  python3-pip
)

for pkg in "${TOOLS[@]}"; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    cecho green "   --$pkg 已安装"
    continue
  fi

apt -o Dpkg::Progress-Fancy="0" install -y "$pkg" >/dev/null 2>&1 &
pid=$!
progress_bar_task "$pid" "$pkg"
wait "$pid"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    cecho green "  --$pkg 已安装"
  else
    cecho yellow "     --$pkg 安装失败"
    apt_run "尝试修复" --fix-broken install -y
    dpkg --configure -a >/dev/null 2>&1
apt -o Dpkg::Progress-Fancy="0" install -y "$pkg" >/dev/null 2>&1 &
pid=$!
progress_bar_task "$pid" "$pkg"
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
cecho white "--中文语言环境已配置 执行 exit ，重新连接ssh后即可生效
重连后您可使用 ls /not-exist 检查来检查是否配置成功 "
#===================｜清理｜======================
cecho blue bold "13.清理系统垃圾"
apt_run "apt autoremove" autoremove -y
apt autoclean -y >/dev/null 2>&1 && \
cecho green "   --成功"  || \
  cecho red "   --设置失败"
#===================｜后续｜======================
cecho red "----开荒完成，10s后将自动部署ppanel后端，如无须部署请输入^C结束脚本---"
sleep 10
curl -fsSL https://get.docker.com | sh
systemctl start docker || cecho red "   --docker启动失败"
systemctl enable docker || cecho red "   --docker启动失败"
mkdir -p /root/ppanel/
mkdir -p /root/ppanel/ppanel-config/
touch /root/ppanel/ppanel-config/ppanel.yaml
touch /root/ppanel/docker-compose.yml
cat > /root/ppanel/ppanel-config/ppanel.yaml <<'EOF'
# 数据库配置
database:
  type: mysql
  host: localhost
  port: 3306
  username: ppanel
  password: Cici080306
  database: ppanel

# Redis 配置
redis:
  host: localhost
  port: 6379
  password: ""
  db: 0

# 服务配置
server:
  host: 0.0.0.0
  port: 8080

# CORS 配置（重要：允许前端域名访问）
cors:
  allow_origins:
    - "https://node.vesper36.top"
    - "http://localhost:3000"  # 开发环境
  allow_methods:
    - GET
    - POST
    - PUT
    - DELETE
    - OPTIONS
  allow_headers:
    - "*"

# JWT 配置
jwt:
  secret: "1fe4b9162dbb82c83387537a969b43ab"
  expire: 7200  # 2小时

# API 配置
api:
  prefix: "/api"
  version: "v1"
  
EOF
cd /root/ppanel/

if ! docker run -d \
  --name ppanel-mysql \
  -e MYSQL_ROOT_PASSWORD=Cici080306 \
  -e MYSQL_DATABASE=ppanel \
  -e MYSQL_USER=ppanel \
  -e MYSQL_PASSWORD=Cici080306 \
  -p 3306:3306 \
  -v ppanel-mysql-data:/var/lib/mysql \
  mysql:5.7 \
  >/dev/null 2>&1
then
  echo red "MySQL 容器启动失败"
  docker logs ppanel-mysql
  exit 1
fi

sleep 10
if !  docker run -d \
  --name ppanel-redis \
  -p 6379:6379 \
  -v ppanel-redis-data:/data \
  redis:7-alpine \
  >/dev/null 2>&1
then
  echo red "Redis 容器启动失败"
  docker logs ppanel-mysql
  exit 1
fi

docker pull ppanel/ppanel:latest >/dev/null 2>&1 || cecho red "   --镜像拉取失败"
docker run -d \
  --name ppanel-backend \
  -p 8080:8080 \
  -v $(pwd)/config.yaml:/app/config.yaml \
  --link ppanel-mysql:mysql \
  --link ppanel-redis:redis \
  ppanel/ppanel:latest \
  >/dev/null 2>&
cd /root/
docker exec ppanel-backend ./gateway migrate >/dev/null 2>&1  || cecho red "   --执行数据库迁移取失败"
docker ps
apt update -y >/dev/null 2>&
apt upgrade -y >/dev/null 2>&
apt install -y nginx >/dev/null 2>&
systemctl start nginx >/dev/null 2>&
systemctl enable nginx >/dev/null 2>&
cd /root/
mkdir -p /etc/nginx/ssl/
mkdir -p /etc/nginx/ssl/vesper36.top/
touch /etc/nginx/ssl/vesper36.top/fullchain.pem
touch /etc/nginx/ssl/vesper36.top/privkey.pem
mkdir -p /etc/nginx/ssl/vesper36.com/
touch /etc/nginx/ssl/vesper36.com/fullchain.pem
touch /etc/nginx/ssl/vesper36.com/privkey.pem
cat > /etc/nginx/ssl/vesper36.top/fullchain.pem <<'EOF'
-----BEGIN CERTIFICATE-----
MIIFETCCA/mgAwIBAgIUXbri9QuVhQZV81nxtyY9AZFYjhIwDQYJKoZIhvcNAQEL
BQAwgYsxCzAJBgNVBAYTAlVTMRkwFwYDVQQKExBDbG91ZEZsYXJlLCBJbmMuMTQw
MgYDVQQLEytDbG91ZEZsYXJlIE9yaWdpbiBTU0wgQ2VydGlmaWNhdGUgQXV0aG9y
aXR5MRYwFAYDVQQHEw1TYW4gRnJhbmNpc2NvMRMwEQYDVQQIEwpDYWxpZm9ybmlh
MB4XDTI1MTIyMTE2MTcwMFoXDTI2MDMyMTE2MTcwMFowYjEZMBcGA1UEChMQQ2xv
dWRGbGFyZSwgSW5jLjEdMBsGA1UECxMUQ2xvdWRGbGFyZSBPcmlnaW4gQ0ExJjAk
BgNVBAMTHUNsb3VkRmxhcmUgT3JpZ2luIENlcnRpZmljYXRlMIIBIjANBgkqhkiG
9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw3LJgyETUPlOZIWgR/UYthJtMiU+Vc06ymFK
8MsFVcuGrDR5+klEX+OQVR+/tH7S+YRUlJEDeN+htSZ5sU5LDZNDZyzIMakfHDyi
U7S75ym4chr+cXYCQ10nBjMmuVB/79cpti1JDvtuJdWFli98IuxtzN7PsAoNXOJK
wFdeY90Rvvb/pWA2qs/IYzOQA7VSFxAQmyNys2fbrbasFfqvoiDCm/uJ3QjPbSR2
Y0+fiNJRCI6jA5AP6yQzMnN8l7b0sAXLkcAHvPhODFf1yZtuGq/Ir1mvss/G1Wzt
zeXVkvf7sfIWTLunp678VrHjJnK32vuSvuqxmZYrb8EzHRi8yQIDAQABo4IBkzCC
AY8wDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggrBgEFBQcD
ATAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBRWggkF9SNG9FXqS5/tl1Bt33z37zAf
BgNVHSMEGDAWgBQk6FNXXXw0QIep65TbuuEWePwppDBABggrBgEFBQcBAQQ0MDIw
MAYIKwYBBQUHMAGGJGh0dHA6Ly9vY3NwLmNsb3VkZmxhcmUuY29tL29yaWdpbl9j
YTCBkwYDVR0RBIGLMIGIghQqLmFkbWluLnZlc3BlcjM2LnRvcIISKi5hcGkudmVz
cGVyMzYudG9wghMqLmJsb2cudmVzcGVyMzYudG9wghMqLm1haWwudmVzcGVyMzYu
dG9wghQqLnBhbmVsLnZlc3BlcjM2LnRvcIIOKi52ZXNwZXIzNi50b3CCDHZlc3Bl
cjM2LnRvcDA4BgNVHR8EMTAvMC2gK6AphidodHRwOi8vY3JsLmNsb3VkZmxhcmUu
Y29tL29yaWdpbl9jYS5jcmwwDQYJKoZIhvcNAQELBQADggEBAHtiCZwMOxauv1Z4
c3QhDkqeFbepKisR5yawg3t2dkBo7p5dr902Eq7rHOagRvw7fFLERhjm7HvWmZC2
Ax4AuQkqInphJxNMgPdPnUjedhXqdbt+ugDridjtHX7DWBx+0TXh/Oo+8FBAjp4Y
ZnE0X0fmWE9fbGNmis+gqxnhQbfsfawWhfsxqyDFKoBJgV5Q7aCDZlhqsDqtaS8N
qFJEiF3YLSSEI6NHM4/fhbAy2pFMshIj2xB48nJekNswiWjeOSk5ffJhr2WGGxE1
FYbewFloI3HOk8jomXY///BABagfcjQnsoRRWdksooc8yLBHNrXzmXkXVhTpKvmq
9GXOQAA=
-----END CERTIFICATE-----
EOF
cat > /etc/nginx/ssl/vesper36.top/privkey.pem <<'EOF'
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDDcsmDIRNQ+U5k
haBH9Ri2Em0yJT5VzTrKYUrwywVVy4asNHn6SURf45BVH7+0ftL5hFSUkQN436G1
JnmxTksNk0NnLMgxqR8cPKJTtLvnKbhyGv5xdgJDXScGMya5UH/v1ym2LUkO+24l
1YWWL3wi7G3M3s+wCg1c4krAV15j3RG+9v+lYDaqz8hjM5ADtVIXEBCbI3KzZ9ut
tqwV+q+iIMKb+4ndCM9tJHZjT5+I0lEIjqMDkA/rJDMyc3yXtvSwBcuRwAe8+E4M
V/XJm24ar8ivWa+yz8bVbO3N5dWS9/ux8hZMu6enrvxWseMmcrfa+5K+6rGZlitv
wTMdGLzJAgMBAAECggEAARsXJ/zGuGb3Gi5/Xg9CJbv49JdG9DYf2dR75HZ7Mz8R
jGV6z/9PubmQSX41sXaLCKP51O71HBJePqe9eVLxR1377z61OA+C5r//eYXEqMwq
bpekgbPVoD5YrpPl6WQazs3JPwfTXMuJyTQ23npD5r0VUFsHLDHPKliSOU0rpYww
hUIGJ7MGjc9Nvys7KpVb39EER0+n8X9DJzQ13KHH/AS4aIGiA27MPl2TwADaA7nm
GGcQFxEuB392wd0ozR+KWjunGHQ2gvWmSO7Vo4koOF0dD5oeqW05xqTZ8K+HCcgJ
dNlCRl+yH6CEqggqXCFGG8pyEHIFPfZzlVQGRBoSAQKBgQDvRNCXWHogYuzEmOMY
kjB1zxBJZiqAMoyMzPbltu3K6bkdZ1Qr7l8aGwi6f25DildsNGZUYaDIgYVo5dvE
yqdgRaU9H0AiwE9gkJKe/5+XxlPrrDMgkvcumhQY3xUSKA5MDBo3nFg/1+jaAM0V
CwlYvG6bVkpJNFq4Yd7j+BfN4QKBgQDRHYlm1Zx0JpHal6eAaJhtjujKkhVapduw
ClYZMKA2mhfRGLu4VEgr0YqrnDc7j4YQQP5EUy5QnDsyUrnHWNaAItkmQuzc/09r
1q7Z/D9jgHO77nOznUzbJwfKNMZ1vdjQc6QBL7fX2P8ZHl1+F8xZIyOS0uO6+pHs
t3DPv2u76QKBgHDCCF9apes/U39u4Y8Bze6nD3DXwe26ZLwyF6S4KaY3sTJnMKan
ZpAh72IcjbUsq/hlVVgszh3P1DRUJta9/lUDXVTJtmrqID5Mw5xEsUxQfdoRw+J1
ACIpIJF8CC0PTXWPOoe8mWY09RpPyFZDZjs4ShPQfZ+0GZDNJsJed7FhAoGAIxh4
8fhRzLCYc/5Vz1g+lMySR0UjLlZ9u1rQvmOJ0AAmlSI4hyQmBKyjQE/0eRuKXXn6
8o6fTEocKUL3CPzg6xpuJVzAEgsLUkbyi4UpQlLRma3YX0G8H1+6j/YxhJs7Iyj1
UnmmuiQiFB4jhMELu74I/2BDdiMNkJPs7ADtXNkCgYEAszvroPrkIRcmLuGnFlAe
KJf37vcR3lxJtYBgDtFJonZlsWhhozXbKpADGGRlsG8XESCxffXDSV312hTBQStR
gJ17Ua5WzAFbijunvZt/U9T/Rb9ndUKratoxjhN0pyi5vganbfMZuiGjh1PsWvoW
xZKGhiXBpaI+fCiIbV3jZhU=
-----END PRIVATE KEY-----
EOF
cat > /etc/nginx/ssl/vesper36.com/fullchain.pem <<'EOF'
-----BEGIN CERTIFICATE-----
MIIF1jCCBL6gAwIBAgIUSAatPLPyyZt+QIucrNnwU+GMlj8wDQYJKoZIhvcNAQEL
BQAwgYsxCzAJBgNVBAYTAlVTMRkwFwYDVQQKExBDbG91ZEZsYXJlLCBJbmMuMTQw
MgYDVQQLEytDbG91ZEZsYXJlIE9yaWdpbiBTU0wgQ2VydGlmaWNhdGUgQXV0aG9y
aXR5MRYwFAYDVQQHEw1TYW4gRnJhbmNpc2NvMRMwEQYDVQQIEwpDYWxpZm9ybmlh
MB4XDTI1MTIwOTA1MTQwMFoXDTQwMTIwNTA1MTQwMFowYjEZMBcGA1UEChMQQ2xv
dWRGbGFyZSwgSW5jLjEdMBsGA1UECxMUQ2xvdWRGbGFyZSBPcmlnaW4gQ0ExJjAk
BgNVBAMTHUNsb3VkRmxhcmUgT3JpZ2luIENlcnRpZmljYXRlMIIBIjANBgkqhkiG
9w0BAQEFAAOCAQ8AMIIBCgKCAQEAleE7f58/kBIDwhCJnX5kyIvAqZNW39wMKSmQ
9deJYeMXCAbiaNL0ic8BXni3PUdeci3P8oFkAysububQAwB7Cl/9hEOnFcNqr+P3
8Tg1DS3rweDACFSQF/E/B8hKTXnR90dUAMemeHYyEd8UleJaGnC/lFEtEf0AP/75
D7//L8GgHbNEQlVguYCIs0x/LW42oCnHoG/vdREhhgAv1U4nEYmCdHalD8d7inYp
qFCpbt/PPsAkilh9LvYsqi0I3IN2x9BDnKlJKpvQXGGTlqaPbu8fag3NIqWtrbK2
Mu61lXKFXP7WwVExR0IP3+N0fMFQ1DtPFZptfCo5Dq04DGD71QIDAQABo4ICWDCC
AlQwDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggrBgEFBQcD
ATAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBRD3d7G8Z3Q/QTdwuPXZO4bqsYYVjAf
BgNVHSMEGDAWgBQk6FNXXXw0QIep65TbuuEWePwppDBABggrBgEFBQcBAQQ0MDIw
MAYIKwYBBQUHMAGGJGh0dHA6Ly9vY3NwLmNsb3VkZmxhcmUuY29tL29yaWdpbl9j
YTCCAVcGA1UdEQSCAU4wggFKghQqLmFkbWluLnZlc3BlcjM2LmNvbYIRKi5haS52
ZXNwZXIzNi5jb22CEiouYXBpLnZlc3BlcjM2LmNvbYITKi5ibG9nLnZlc3BlcjM2
LmNvbYIUKi5jbG91ZC52ZXNwZXIzNi5jb22CEiouaXBhLnZlc3BlcjM2LmNvbYIU
Ki5wYW5lbC52ZXNwZXIzNi5jb22CFCoucHJveHkudmVzcGVyMzYuY29tghQqLnNo
YXJlLnZlc3BlcjM2LmNvbYIUKi5zdHVkeS52ZXNwZXIzNi5jb22CGSoudGVjaG5v
bG9neS52ZXNwZXIzNi5jb22CEyoudXNlci52ZXNwZXIzNi5jb22CDioudmVzcGVy
MzYuY29tghIqLnZpcC52ZXNwZXIzNi5jb22CEioudnBzLnZlc3BlcjM2LmNvbYIM
dmVzcGVyMzYuY29tMDgGA1UdHwQxMC8wLaAroCmGJ2h0dHA6Ly9jcmwuY2xvdWRm
bGFyZS5jb20vb3JpZ2luX2NhLmNybDANBgkqhkiG9w0BAQsFAAOCAQEAURIkqIRs
ffeDq9BTXsV65RBWseepjszYbXy4lK8cPDj+NWCEQu80obVNYHMf05Iy1Tc11pLh
G07AVMdeUG5E5oURDkZgSEWeMn7cnba8zIUpW8u5bCRrJ/4lhSzxHF7aFKsicc5D
0IZtX+V90VcGN+Er7dEIVWq+1m4IunJ1/UxGDGehrKN9f3RYoGUiY/W5t6lAFr74
OM42nr53wNfV+vrxBVC9F1KK1unw8rAu2buU2awwh/Z2+UibmbkYx1p49qVg2oG4
snT9ARF//k6/Czvwe9FFR8Ydrpfr7l7U3El7dcvNTrgEHFRcep829FGejx79TEYG
UnHVMkM+VbSUgA==
-----END CERTIFICATE-----
EOF
cat > /etc/nginx/ssl/vesper36.com/privkey.pem <<'EOF'
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCV4Tt/nz+QEgPC
EImdfmTIi8Cpk1bf3AwpKZD114lh4xcIBuJo0vSJzwFeeLc9R15yLc/ygWQDKy5u
5tADAHsKX/2EQ6cVw2qv4/fxODUNLevB4MAIVJAX8T8HyEpNedH3R1QAx6Z4djIR
3xSV4loacL+UUS0R/QA//vkPv/8vwaAds0RCVWC5gIizTH8tbjagKcegb+91ESGG
AC/VTicRiYJ0dqUPx3uKdimoUKlu388+wCSKWH0u9iyqLQjcg3bH0EOcqUkqm9Bc
YZOWpo9u7x9qDc0ipa2tsrYy7rWVcoVc/tbBUTFHQg/f43R8wVDUO08Vmm18KjkO
rTgMYPvVAgMBAAECggEADO4vieUdQLqtJFL07Gd5HmwgJQEXH50GV47EeNEtgwpq
dEDTy6NXgYQgZBwaAuljVoppREyxaiyRhvPWwkuKUezSHFUR1yjSzXXncCIfQZHS
oxlWt+FDxS0E+RDoiCKYYLMApkiTLhVUYIJUblHm4B0WCh+uubyQBvViW19/DomN
/KBgWRqKZ2gDBsCsbXiaedLLwp5cihqfKl045QXmB2QHkuZnv/3kB7URMuRuDolt
OIasOahml1wUkvA6ml3ZwpAJBBt/Z0rZ+P5SyPOs+xnNR+oFYIUitW5X4H/vRx83
vKqV5LlGdPwlrub9E4krpkAbZMUE6IkmeoTa3IsggQKBgQDRjsvfWR9bxdGcMqLy
WO1RBd08PEfmMuaQ8E2/fJZEej0lxJVBjHm0PTrsQsd6PvImVA+36UX4FGAoEXo2
gzM6ZYQFHgPqGkyxU0R+RJwHHbWzhP+Hk5KqU/JQmlPzMl0G68bnZdhvBb9JJakU
dVwfqV5HVAFsB+liJNxRUo+BsQKBgQC3GJ9EmzPeSYLNxQuRcR4ad71lNBDkYaCA
PXqCWyCcK85ySaT1eFzmeI7ICekhSdm/pfZjvWNIttqpc6ABxd5m7SDjHi5nW+lH
nIY6Y/NDR2iskGsIUaePDUZzO1dOP0rKySIV9xVdukjKZIhA8dT5aVuNYFKRdRDM
muHFynshZQKBgAj46jW35SXSxHTBnkRuFksfyycnFZT/nOubvlhyhySLb07Mqe9S
imtzK7Ct80iCpW+Krdmb/Ujv5mYQyYDIAUuAyTRG4rgFRD9bZ1VYrq2HUh5LlX1C
jkcIrRlSYkHJaD5BnhSOQcQPJO+G00Ry+ezJHaZELINpm05+cYhx1n8hAoGBAJ1A
OlmT6mI5RGwxlZPeUPpuaG1o4DElX9GD+5nFZiZ6wR4K/fAM5czTMd3AFUePw8ID
aa+T0pd65CWwtnWPWUmQ0zP8keIXYC0u02GGwkDALbg3eJV2e7AyuJTzHDKJzVSI
lgvDX8hV23poCVWt3TowMH8lgQSIRFtVkh5rnoC5AoGBAKMyoMVMuZFEjA/+B0Xr
HyxtKpX1SlhyAyX6h88Kr8Ig98i9f6Y3PgA79cxdmCbb9XLmf6iOIMSgFtoDS2NJ
zK1AGXvYtJ5M/e2F5bDkP7xhpXaYqR4fYN6bEqM4KVqqM0NFhBBZugsYtFB5Iz7C
pgnwunETfomS54p5NY5dz+jP
-----END PRIVATE KEY-----
EOF
chmod 600 /etc/nginx/ssl/vesper36.top/*
chmod 600 /etc/nginx/ssl/vesper36.com/*
touch /etc/nginx/sites-available/ppanel.conf
cat > /etc/nginx/sites-available/ppanel.conf <<'EOF'
server {
    listen 80;
    server_name 01-api.vesper36.top;

    return 301 https://$host$request_uri;
}


server {
    listen 443 ssl http2;
    server_name 01-api.vesper36.top;

    ssl_certificate     /etc/nginx/ssl/vesper36.top/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/vesper36.top/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass http://127.0.0.1:8080;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
ln -s /etc/nginx/sites-available/ppanel.conf \
      /etc/nginx/sites-enabled/ppanel.conf\
          >/dev/null 2>&
nginx -t >/dev/null 2>&
systemctl reload nginx >/dev/null 2>&


#===================｜清理｜======================

cecho white "如有任何问题可反馈至 shuhany86@gmail.com"
cecho purple "  -------感谢使用本脚本------"
