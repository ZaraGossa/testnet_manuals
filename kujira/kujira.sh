#!/bin/bash
echo "=================================================="
echo -e "\033[0;35m"
echo " :::    ::: ::::::::::: ::::    :::  ::::::::  :::::::::  :::::::::: ::::::::  ";
echo " :+:   :+:      :+:     :+:+:   :+: :+:    :+: :+:    :+: :+:       :+:    :+: ";
echo " +:+  +:+       +:+     :+:+:+  +:+ +:+    +:+ +:+    +:+ +:+       +:+        ";
echo " +#++:++        +#+     +#+ +:+ +#+ +#+    +:+ +#+    +:+ +#++:++#  +#++:++#++ ";
echo " +#+  +#+       +#+     +#+  +#+#+# +#+    +#+ +#+    +#+ +#+              +#+ ";
echo " #+#   #+#  #+# #+#     #+#   #+#+# #+#    #+# #+#    #+# #+#       #+#    #+# ";
echo " ###    ###  #####      ###    ####  ########  #########  ########## ########  ";
echo -e "\e[0m"
echo "=================================================="

sleep 2

# set vars
if [ ! $NODENAME ]; then
	read -p "Enter node name: " NODENAME
	echo 'export NODENAME='$NODENAME >> $HOME/.bash_profile
fi
echo "export WALLET=wallet" >> $HOME/.bash_profile
echo "export CHAIN_ID=harpoon-3" >> $HOME/.bash_profile
source $HOME/.bash_profile

echo '================================================='
echo 'Your node name: ' $NODENAME
echo 'Your wallet name: ' $WALLET
echo 'Your chain name: ' $CHAIN_ID
echo '================================================='
sleep 2

echo -e "\e[1m\e[32m1. Updating packages... \e[0m" && sleep 1
# update
sudo apt update && sudo apt upgrade -y

echo -e "\e[1m\e[32m2. Installing dependencies... \e[0m" && sleep 1
# packages
sudo apt install curl build-essential git wget jq make gcc tmux -y

# install go
ver="1.18.1"
cd $HOME
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
rm "go$ver.linux-amd64.tar.gz"
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bash_profile
source ~/.bash_profile
go version

echo -e "\e[1m\e[32m3. Downloading and building binaries... \e[0m" && sleep 1
# download binary
cd $HOME
git clone https://github.com/Team-Kujira/core kujira-core && cd kujira-core
make install

# config
kujirad config chain-id $CHAIN_ID
kujirad config keyring-backend file

# init
kujirad init $NODENAME --chain-id $CHAIN_ID

# download genesis
wget -qO $HOME/.kujira/config/genesis.json "https://raw.githubusercontent.com/Team-Kujira/networks/master/testnet/harpoon-3.json"
wget -qO $HOME/.kujira/config/addrbook.json "https://raw.githubusercontent.com/Team-Kujira/networks/master/testnet/addrbook.json"

# set minimum gas price
sed -i -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0ukuji\"/" $HOME/.kujira/config/app.toml

# set peers and seeds
SEEDS=""
PEERS="861f4624276d80aa538ad446ce608910ca24940d@148.251.177.45:11656,f9346e4680529c222f374dfb62eb53769a10d656@116.203.210.205:26656,d932ab29136c77579d31f3f8ec364e33e1e0e272@188.34.178.187:36656,7bf8bb44be721b486b13dafe47ef092f914452cb@188.34.178.184:36656,32987bd6d2c8e98aef650e08e8e270e07578f888@195.201.164.223:26656,bee48b090b97ef1a8adca4adecf897e5d29c6909@3.39.245.44:26656,dfa8f5ece785837e040f6c3e1d50e8407b7db9b9@62.171.174.247:26656"
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.kujira/config/config.toml

# disable indexing
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $HOME/.kujira/config/config.toml

# enable prometheus
sed -i -e "s/prometheus = false/prometheus = true/" $HOME/.kujira/config/config.toml

# config pruning
pruning="custom"
pruning_keep_recent="100"
pruning_keep_every="0"
pruning_interval="50"
sed -i -e "s/^pruning *=.*/pruning = \"$pruning\"/" $HOME/.kujira/config/app.toml
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"$pruning_keep_recent\"/" $HOME/.kujira/config/app.toml
sed -i -e "s/^pruning-keep-every *=.*/pruning-keep-every = \"$pruning_keep_every\"/" $HOME/.kujira/config/app.toml
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"$pruning_interval\"/" $HOME/.kujira/config/app.toml

# sync using State Sync
SNAP_RPC="https://kujira-testnet-rpc.polkachu.com:443"
LATEST_HEIGHT=$(curl -s $SNAP_RPC/block | jq -r .result.block.header.height); \
BLOCK_HEIGHT=$((LATEST_HEIGHT - 2000)); \
TRUST_HASH=$(curl -s "$SNAP_RPC/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)
sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ; \
s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"$SNAP_RPC,$SNAP_RPC\"| ; \
s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT| ; \
s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"| ; \
s|^(seeds[[:space:]]+=[[:space:]]+).*$|\1\"\"|" $HOME/.kujira/config/config.toml

# reset
kujirad tendermint unsafe-reset-all

echo -e "\e[1m\e[32m4. Starting service... \e[0m" && sleep 1
# create service
sudo tee /etc/systemd/system/kujirad.service > /dev/null <<EOF
[Unit]
Description=kujira
After=network-online.target

[Service]
User=$USER
ExecStart=$(which kujirad) start
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# start service
sudo systemctl daemon-reload
sudo systemctl enable kujirad
sudo systemctl restart kujirad

echo '=============== SETUP FINISHED ==================='
echo -e 'To check logs: \e[1m\e[32mjournalctl -u kujirad -f -o cat\e[0m'
echo -e 'To check sync status: \e[1m\e[32mcurl -s localhost:26657/status | jq .result.sync_info\e[0m'
