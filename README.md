Dockerized ISC DHCP server based on CentOS 7 

# Introduction
On CentOS the DHCP server (`dhcpd`) is a `systemd` service. In this image, the server process is executed 
directly on container launch (Dockerfile `CMD`), without `systemd`. The image uses [dumb-init](#dumb-init) 
to address the problems that appear because CentOS (any init-system based Linux, for the matter) always 
expects and supposes that the 1st process is the init-system.

# DHCP server
The command used to launch the DHCP server is

`/usr/sbin/dhcpd -f -d -cf /etc/dhcp/dhcpd.conf -user dhcpd -group dhcpd --no-pid`

which is what CentOS' default systemd unit file uses, except the `-d` flag added to reconfigure logging to use
stdout/stderr instead of SYSLOG. 

The DHCP server needs access to the network interface informations to be able to interpret its configuration - 
in fact, the DHCP configuration is network interface agnostic and it's up to the server to match the 
configurations with the actual network situation. If the DHCP service is meant to serve networks of the Docker 
host, it has to be given access to the host's network interfaces with the Docker run flag `--net host`

The `-cf` flag tells the server to expect its configuration file to be located at `/etc/dhcp/dhcpd.conf`. The
file could be added at build time using a 
  
`ADD <dhcpd_conf_filepath_on_host> /etc/dhcp/dhcpd.conf` 

instruction in the Dockerfile, where `dhcpd_conf_filepath_on_host` is the absolute filepath of the 
configuration file on the Docker host. However, that would imply that the image has to be rebuild every time 
the configuration changes. To avoid this, this image rather expects that the configuration file is mounted 
from the host at runtime using the Docker run flag 
  
`-v <dhcpd_conf_filepath_on_host>:/etc/dhcp/dhcpd.conf:ro` 

The  `...:ro` flag tells Docker to mount it as read-only.   

The DHCP server stores its leases in `/var/lib/dhcpd`. This folder should be made persistant to insure service
continuation in case of DHCP server restarts (faulty or not). The easiest way is to use a Docker volume 

`-v <volume_name>:/var/lib/dhcpd` 

Related documentation:
- [DHCP manual](https://linux.die.net/man/8/dhcpd)
- [Docker host networking](https://docs.docker.com/network/host/)
- [Docker bind mounts](https://docs.docker.com/storage/bind-mounts/)

# dumb-init
Since CentOS uses `systemd` and supposes that the process with ID 1 is always `systemd`, running a single process 
inside a CentOS container comes with a range of quirks explained in the 
[dumb-init documentation](https://github.com/Yelp/dumb-init). One important aspect is that affected containers 
without `dumb-init` ignore process signals like `SIGTERM`. The Docker client "solves" this by killing the 
container process if the stop command times out but other pieces of software tend to get confused if processes 
ignore common signals. 

Hence, while it's absolutely possible to run the DHCP server directly using the command given above, it's just 
good practice to add `dumb-init` for proper signal handling. The Dockerfile contains the instructions to install 
the latest binary from GitHub and the launch instruction is prepended with `dumb-init` to become 

`dumb-init /usr/sbin/dhcpd ...`

Related documentation:
- [dumb-init GitHub repository](https://github.com/Yelp/dumb-init)
- [Blog article](https://engineeringblog.yelp.com/2016/01/dumb-init-an-init-for-docker.html) from the Yelp 
  engineers which explains why they created `dumb-init`
- [StackOverflow question whether dumb-init is really needed](https://stackoverflow.com/questions/37374310/how-critical-is-dumb-init-for-docker)

# systemd integration on the Docker host: systemd-docker & dumb-init
If the Docker host runs on a Linux OS using `systemd`, it makes sense to run the Docker containers as `systemd`  
services (not to be confused with the `systemd` inside the container, which never runs). Tools like 
[systemd-docker](https://github.com/DonTseTse/systemd-docker) allow to improve integration: it makes `systemd` 
supervise the actual container process instead of the Docker client process. The integration into `systemd` also 
shows the purpose of `dumb-init`: without it, the container ignores termination signals, which leaves `systemd` 
helpless when it tries to shutdown such a container. 

A `systemd` service unit file example is provided below in the [Execution section](#execution)

# How-to
## Image build 

In the folder where the Dockerfile is, execute:

`docker build -t <image_name> .` where `image_name` is the name given to the image in the local Docker image 
registry

## Execution
Supposing that you want to run the container on the host's network interfaces, execute:

`docker run --net host -v <dhcpd_conf>:/etc/dhcp/dhcpd.conf:ro -v <volume_name>:/var/lib/dhcp -d <image_name>`

where
- `image_name` is the name choosen during the build step (to list available images run `docker images`)
- the role of the `--net` and `-v` flags is explained in the [DHCP server section](#dhcp-server) 
- `-d` detaches the console to daemonize the process

To run that same container as a `systemd` unit using `systemd-docker` (supposed to be in `/usr/bin`), 
a service unit file could look like:
```ini
[Unit]
Description=DHCP service
After=docker.service
Requires=docker.service
 
[Service]
ExecStart=/usr/bin/systemd-docker run --net host -v <dhcpd_conf_filepath>:/etc/dhcp/dhcpd.conf:ro --name <container_name> --rm <image_name>
Restart=always

[Install]
WantedBy=multi-user.target
```
When `systemd-docker` is used, a explicit container name (`--name <container_name>`) as well as automatic
removal (`--rm`) is compulsory and the `-d` flag is not needed. 
