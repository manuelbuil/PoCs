//go:build windows
// +build windows
package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"strings"
	"time"

	"github.com/Microsoft/hcsshim"
)

func main() {
	fmt.Println("Starting")
	CalicoHnsNetworkName := "testing"
	networkAdapter, err := findInterface("10.85.9.170")
	if err != nil {
		fmt.Println("ERROR when findInterface")
		os.Exit(1)
	}
	fmt.Printf("This is networkAdapter: %s\n", networkAdapter)
	network := hcsshim.HNSNetwork{
		Type:               "Overlay",
		Name:               CalicoHnsNetworkName,
		NetworkAdapterName: networkAdapter,
		Subnets: []hcsshim.Subnet{
			{
				AddressPrefix:  "192.168.255.0/30",
				GatewayAddress: "192.168.255.1",
				Policies: []json.RawMessage{
					[]byte("{ \"Type\": \"VSID\", \"VSID\": 9999 }"),
				},
			},
		},
	}

	fmt.Println("About to create network")
	if _, err := network.Create(); err != nil {
		fmt.Printf("error creating the %s network: %v \n", CalicoHnsNetworkName, err)
		os.Exit(1)
	}

	fmt.Println("Waiting for network to exist")
	// Check if network exists. If it does not after 5 minutes, fail
	for start := time.Now(); time.Since(start) < 5*time.Minute; {
		network2, err := hcsshim.GetHNSNetworkByName(CalicoHnsNetworkName)
		if err == nil {
			fmt.Printf("Network FOUND! %v \n", network2)
		}
	}

	fmt.Println("Bye!")
}

// findInterface returns the name of the interface that contains the passed ip
func findInterface(ip string) (string, error) {
	iFaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}

	for _, iFace := range iFaces {
		addrs, err := iFace.Addrs()
		if err != nil {
			return "", err
		}
		fmt.Printf("evaluating if the interface: %s with addresses %v, contains ip: %s \n", iFace.Name, addrs, ip)
		for _, addr := range addrs {
			if strings.Contains(addr.String(), ip) {
				return iFace.Name, nil
			}
		}
	}

	return "", fmt.Errorf("no interface has the ip: %s", ip)
}
