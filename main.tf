terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}

resource "docker_network" "jenkins_network" {
  name = "jenkins"
}

resource "docker_container" "jenkins" {
  image = var.jenkins_image
  name  = "jenkins-blueocean"
  ports {
    internal = 8080
    external = var.jenkins_port
  }
  ports {
    internal = 50000
    external = 50000
  }
  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["jenkins"]
  }
  volumes {
    volume_name    = docker_volume.jenkins_home.name
    container_path = "/var/jenkins_home"
  }
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }
  env = [
    "DOCKER_HOST=tcp://docker:2376",
    "DOCKER_TLS_VERIFY=1",
    "DOCKER_CERT_PATH=/certs/client"
  ]
}

resource "docker_volume" "jenkins_home" {
  name = "jenkins_home"
}

resource "docker_container" "dind" {
  image = var.dind_image
  name  = "jenkins-docker"
  privileged = true
  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["docker"]
  }
  volumes {
    volume_name    = docker_volume.dind_certs.name
    container_path = "/certs/client"
  }
  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]
}

resource "docker_volume" "dind_certs" {
  name = "dind_certs"
}