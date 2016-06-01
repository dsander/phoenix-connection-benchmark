#/bin/sh
set -e

cat <<EOF >> /etc/sysctl.conf
fs.file-max=22000500
fs.nr_open=30000500
net.ipv4.tcp_mem='10000000 10000000 10000000'
net.ipv4.tcp_rmem='1024 4096 16384'
net.ipv4.tcp_wmem='1024 4096 16384'
net.core.rmem_max=16384
net.core.wmem_max=16384
EOF

cat <<EOF >> /etc/security/limits.conf
root      hard    nofile      30000000
root      soft    nofile      30000000
EOF

wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb
sudo dpkg -i erlang-solutions_1.0_all.deb
curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
sudo apt-get install -y --no-install-recommends elixir git esl-erlang nodejs htop
sudo update-locale LC_ALL=en_US.UTF-8

rm -rf chat
git clone https://github.com/chrismccord/phoenix_chat_example.git chat
cd chat
git checkout 02bbbc8a295542146aef4e347dcbdc5fd0aadd69
wget https://dl.dropboxusercontent.com/u/62784372/benchmark.patch
cat benchmark.patch | patch -p1

export MIX_ENV=prod
export PORT=4000

mix local.hex --force
mix local.rebar --force
mix deps.get
mix deps.compile
npm install -g brunch
npm install
brunch build
echo manual | sudo tee /etc/init/docker.override
reboot
