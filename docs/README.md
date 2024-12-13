# README - ENTREGABLE 3

<!-- markdownlint-disable MD033 -->
<div style="text-align: justify;">

Realizado por **Jesús Javier Gallego Ibáñez** y **Aday García López**.

Asignatura: **Virtualización de Sistemas**.

Este documento contiene las instrucciones necesarias para replicar el proceso completo de despliegue del proyecto. Es decir, la configuración para desplegar un servidor Jenkins y su infraestructura asociada mediante Terraform.

## Pasos para replicar el despliegue del proyecto

### Crear un repositorio en GitHub

    Entramos en la web de GitHub y creamos un repositorio. Desde la terminal de nuestro   ordenador clonamos este repositorio y creamos los directorios necesarios para agrupar   bien este proyecto.

### Creamos y configuramos los archivos necesarios

Creamos los archivos:

1. *Dockerfile:* Este archivo describe cómo crear una imagen personalizada de Jenkins. A partir de la imagen oficial de Jenkins, agrega herramientas necesarias como el cliente de Docker y plugins específicos como Blue Ocean y docker-workflow. Esto permite que Jenkins sea capaz de ejecutar tareas relacionadas con Docker directamente desde los pipelines.

        FROM jenkins/jenkins:2.479.2-jdk17
        USER root
        RUN apt-get update && apt-get install -y lsb-release
        RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
            https://download.docker.com/linux/debian/gpg
        RUN echo "deb [arch=$(dpkg --print-architecture) \
            signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
            https://download.docker.com/linux/debian \
            $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        RUN apt-get update && apt-get install -y docker-ce-cli
        USER jenkins
        RUN jenkins-plugin-cli --plugins "blueocean docker-workflow token-macro json-path-api"

1. *Jenkinsfile:* Es un script que define el pipeline que Jenkins debe ejecutar. Contiene las instrucciones paso a paso para construir, probar y empaquetar una aplicación Python. Utiliza imágenes Docker específicas como agentes, asegurando un entorno controlado y limpio para cada etapa del proceso.

        pipeline {
            agent none
            options {
                skipStagesAfterUnstable()
            }
            stages {
                stage('Build') {
                    agent {
                        docker {
                            image 'python:3.12.0-alpine3.18'
                        }
                    }
                    steps {
                        sh 'python -m py_compile sources/add2vals.py sources/calc.py'
                        stash(name: 'compiled-results', includes: 'sources/*.py*')
                    }
                }
                stage('Test') {
                    agent {
                        docker {
                            image 'qnib/pytest'
                        }
                    }
                    steps {
                        sh 'py.test --junit-xml test-reports/results.xml sources/test_calc. py'
                    }
                    post {
                        always {
                            junit 'test-reports/results.xml'
                        }
                    }
                }
                stage('Deliver') {
                    agent any
                    environment {
                        VOLUME = '$(pwd)/sources:/src'
                        IMAGE = 'cdrx/pyinstaller-linux:python2'
                    }
                    steps {
                        dir(path: env.BUILD_ID) {
                            unstash(name: 'compiled-results')

                        }
                    }
                    post {
                        success {
                            archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals"
                            sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
                        }
                    }
                }
            }
        }

1. *main.tf:* Este archivo es la base de la configuración de Terraform. Define los recursos necesarios para la infraestructura, como los contenedores de Jenkins y DinD, la red y los volúmenes Docker. Permite que la infraestructura se despliegue automáticamente siguiendo las especificaciones definidas.

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
          volumes {
            host_path      = "/var/jenkins_home/workspace"
            container_path = "/var/jenkins_home/workspace"
          }
          env = [
            "DOCKER_HOST=unix:///var/run/docker.sock"
          ]
          user = "0" # Ejecutar como root
          command = [
            "/bin/bash", "-c",
            "whoami && groupadd docker && usermod -aG docker jenkins && /usr/bin/tini -- /  usr/      local/bin/jenkins.sh"
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

1. *variables.tf:* Almacena valores que se usan en el archivo 'main.tf', como el nombre de la imagen de Jenkins o los puertos configurados. Esto hace que la configuración sea más flexible y fácil de actualizar, ya que centraliza los parámetros modificables en un solo lugar.

        variable "jenkins_image" {
          default = "myjenkins-blueocean"
        }

        variable "jenkins_port" {
          default = 8080
        }

        variable "dind_image" {
          default = "docker:dind"
        }

### Constriumos la imagen personaliza de Jenkins

   Para ello, utilizamos el comando de Docker:

    docker build -t myjenkins-blueocean .

### Desplegamos los contenedores Docker con Terraform

Utilizamos:

    terraform init
    terraform apply

Y respondemos "yes" cuando se nos pregunte `Do you want to perform these actions?'

De esta forma, ya tendremos los dos contenedores desplegados; el contenedor jenkins-blueocean y el contenedor jenkins-docker.

### Configuramos Jenkins

Primero, desbloqueamos Jenkins con la clave que encontramos al ejecutar:

    docker exec jenkins-blueocean cat /var/jenkins_home/secrets/initialAdminPassword

Posteriormente, instalamos los plugins recomendados y necesarios y creamos un usuario administrador.

### Creamos y configuramos el pipeline en Jenkins

Primero, configuramos el pipeline desde el panel principal de Jenkins.

Después, configuramos el origen del Jenkinsfile.

Para finalizar, guardamos la configuración del pipeline y lo ejecutamos desde el menú lateral del mismo.

</div>
<!-- markdownlint-enable MD033 -->