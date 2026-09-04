resource "yandex_vpc_network" "main" {
  name = "diplom-network"
}

resource "yandex_vpc_gateway" "nat" {
  name = "nat-gateway"

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private" {
  name       = "private-route-table"
  network_id = yandex_vpc_network.main.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat.id
  }
}

resource "yandex_vpc_subnet" "public" {
  name           = "public"
  v4_cidr_blocks = ["10.10.10.0/24"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
}

resource "yandex_vpc_subnet" "private_a" {
  name           = "private-a"
  v4_cidr_blocks = ["10.10.20.0/24"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  route_table_id = yandex_vpc_route_table.private.id
}

resource "yandex_vpc_subnet" "private_b" {
  name           = "private-b"
  v4_cidr_blocks = ["10.10.30.0/24"]
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.main.id
  route_table_id = yandex_vpc_route_table.private.id
}

resource "yandex_vpc_security_group" "load_balancer" {
  name       = "load_balancer-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol          = "TCP"
    port              = 30080
    predefined_target = "loadbalancer_healthchecks"
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "yandex_vpc_security_group" "bastion" {
  name       = "bastion-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "elk" {
  name       = "elk-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["10.10.10.0/24"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["10.10.20.0/24", "10.10.30.0/24"]
    port           = 9200
  }

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["10.10.10.0/24"]
    port           = 5601
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "web" {
  name       = "web-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
  protocol       = "TCP"
  description    = "HTTP from Zabbix"
  port           = 80
  v4_cidr_blocks = ["10.10.10.4/32"]
}

  ingress {
    protocol       = "TCP"
    description    = "Zabbix agent"
    v4_cidr_blocks = ["10.10.10.6/32"]
    port           = 10050
  }

  ingress {
    protocol          = "TCP"
    port              = 10050
    security_group_id = yandex_vpc_security_group.zabbix.id

  }

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["10.10.10.0/24"]
    port           = 22
  }

  ingress {
    description       = "Health checks from Application Load Balancer"
    protocol          = "TCP"
    port              = 80
    predefined_target = "loadbalancer_healthchecks"
  }

  ingress {
    protocol          = "TCP"
    port              = 80
    security_group_id = yandex_vpc_security_group.load_balancer.id
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "zabbix" {
  name       = "zabbix-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["10.10.10.0/24"]
  }

  ingress {
    protocol       = "TCP"
    port           = 8080
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

output "bastion_public_ip" {
  value = yandex_compute_instance.bastion.network_interface[0].nat_ip_address
}

resource "yandex_alb_target_group" "web_a" {
  name = "web-target-group-a"

  target {
    subnet_id  = yandex_vpc_subnet.private_a.id
    ip_address = yandex_compute_instance.web01.network_interface[0].ip_address
  }
}

resource "yandex_alb_target_group" "web_b" {
  name = "web-target-group-b"

  target {
    subnet_id  = yandex_vpc_subnet.private_b.id
    ip_address = yandex_compute_instance.web02.network_interface[0].ip_address
  }
}

resource "yandex_alb_backend_group" "web" {
  name = "web-backend-group"

  http_backend {
    name   = "web-backend"
    weight = 1
    port   = 80
    target_group_ids = [
      yandex_alb_target_group.web_a.id,
      yandex_alb_target_group.web_b.id
    ]

    healthcheck {
      timeout             = "10s"
      interval            = "2s"
      healthy_threshold   = 2
      unhealthy_threshold = 3

      http_healthcheck {
        path = "/"
      }
    }
  }
}

resource "yandex_alb_http_router" "web" {
  name = "web-router"
}

resource "yandex_alb_virtual_host" "web" {
  name           = "web-virtual-host"
  http_router_id = yandex_alb_http_router.web.id

  route {
    name = "web-route"

    http_route {
      http_match {
        path {
          prefix = "/"
        }
      }

      http_route_action {
        backend_group_id = yandex_alb_backend_group.web.id
      }
    }
  }
}

resource "yandex_alb_load_balancer" "web" {
  name = "web-load-balancer"

  network_id = yandex_vpc_network.main.id

  security_group_ids = [
    yandex_vpc_security_group.load_balancer.id
  ]

  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.public.id
    }
  }

  listener {
    name = "http"

    endpoint {
      address {
        external_ipv4_address {}
      }

      ports = [80]
    }

    http {
      handler {
        http_router_id = yandex_alb_http_router.web.id
      }
    }
  }
}