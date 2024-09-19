# doomtown

## install

```bash
git config --local include.path ../.gitconfig
```

```bash
apt -y install tcl tcllib libsqlite3-tcl
```

## push

```bash
git pushall
```

## run

```bash
tclsh ./src/main.tcl --server 8080
```

## setup service

```bash
sudo cp ./doomtown.service /lib/systemd/system/
cp ./example.conf ./local.conf
sudo systemctl enable doomtown
# Allow to run on port 80:
sudo echo 'net.ipv4.ip_unprivileged_port_start=0' > /etc/sysctl.d/50-unprivileged-ports.conf
sudo sysctl --system
```

## start service

```bash
sudo systemctl start doomtown
```

## check service

```bash
sudo journalctl -u doomtown
```