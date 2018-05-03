package main

import (
	"context"
	"fmt"
	"log"
	"time"

	docker "github.com/docker/docker/client"
	"github.com/docker/engine-api/types"
	riemann "github.com/riemann/riemann-go-client"
)

func main() {
	err := realmain()
	if err != nil {
		log.Fatal(err)
	}
}

func realmain() error {
	cli, err := docker.NewEnvClient()
	if err != nil {
		panic(err)
	}
	containers, err := cli.ContainerList(context.Background(), types.ContainerListOptions{})
	if err != nil {
		panic(err)
	}
	for _, container := range containers {
		fmt.Printf("%s %s\n", container.ID[:10], container.Image)
	}
}

func rClient() {
	c := riemann.NewTcpClient("127.0.0.1:5555", 5*time.Second)
	defer c.Close()
	err := c.Connect()
	if err != nil {
		panic(err)
	}
}

func events(c *docker.Container) []riemann.Event {

}
