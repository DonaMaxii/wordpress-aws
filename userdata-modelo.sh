#!/bin/bash

# instalando docker na instancia
sudo yum update -y
sudo yum install docker -y
sudo service docker start
sudo usermod -aG docker ec2-user

# montando sistema EFS
sudo yum install -y amazon-efs-utils
sudo yum install -y nfs-utils
sudo mkdir -p /mnt/efs

#Laço para três tentativas de montagem
EFS_OK=false
for i in {1..3}; do
  if timeout 30 sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport <id-do-sistema-de-arquivos>.efs.us-east-1.amazonaws.com:/ /mnt/efs 2>/dev/null; then
    echo "--> EFS montado com sucesso na tentativa $i" >> /home/ec2-user/efs.log
    EFS_OK=true
    break
  else
    echo "--> Tentativa $i de montagem do EFS falhou, continuando..." >> /home/ec2-user/efs.log
    sleep 5
  fi
done

#Adicionar ponto de montagem ao fstab (persistência)
if [ "$EFS_OK" = true ]; then
  echo "<id-do-sistema-de-arquivos>.efs.us-east-1.amazonaws.com:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=60,retrans=1,noresvport 0 0" | sudo tee -a /etc/fstab
  echo "--> EFS Adicionado ao fstab com sucesso." >> ~/efs.log
else
  echo "--> EFS não disponível - continuando sem armazenamento compartilhado" >> ~/efs.log
fi

# configurando docker compose
mkdir -p /home/ec2-user/wordpress
sudo chown -R ec2-user:ec2-user /home/ec2-user/wordpress
cat << EOF > /home/ec2-user/wordpress/docker-compose.yml
services:
  wordpress:
    image: wordpress:latest
    container_name: wordpress
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: <endpoint-do-banco-de-dados>
      WORDPRESS_DB_USER: <usuario-db>
      WORDPRESS_DB_PASSWORD: <senha-db>
      WORDPRESS_DB_NAME: <nome-inicial-db>
    volumes:
      - /mnt/efs:/var/www/html
    healthcheck:
      test: ["CMD", "curl", "-fs", "http://localhost/wp-login.php"]
      interval: 30s
      timeout: 10s
      retries: 5
EOF

# instalando docker-compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

#Configurando permissões do ponto de montagem
sudo mkdir -p /mnt/efs/wordpress
sudo chown -R 33:33 /mnt/efs/
sudo chmod -R 775 /mnt/efs/

# rodando container app
cd /home/ec2-user/wordpress
docker-compose up -d

