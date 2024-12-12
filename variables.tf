variable "jenkins_image" {
  default = "myjenkins-blueocean"
}

variable "jenkins_port" {
  default = 8080
}

variable "dind_image" {
  default = "docker:dind"
}