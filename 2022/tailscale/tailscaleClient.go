package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"tailscale.com/client/tailscale"
)

func tailScaleClient() {
	tailscale.I_Acknowledge_This_API_Is_Unstable = true

	apiKey := os.Getenv("TAILSCALE_API_KEY")
	tailnet := os.Getenv("TAILSCALE_TAILNET")
	var authMethod tailscale.AuthMethod
	authMethod = tailscale.APIKey(apiKey)

	client := tailscale.NewClient(tailnet, authMethod)

	var myDevFieldOpts tailscale.DeviceFieldsOpts
	// List all your devices
	devices, err := client.Devices(context.Background(), &myDevFieldOpts)
	if err != nil {
		fmt.Println(err)
	}

	hostname, _ := os.Hostname()
	finalNodeIP := ""
	fmt.Printf("There are %d tailscale devices\n", len(devices))
	for _, device := range(devices) {
		if hostname == device.Hostname {
			fmt.Printf("We found the device. The IPs are %v\n", device.Addresses)
//			for _, address := range(device.Addresses) {
//				if utilsnet.IsIPv4String(address) {
//					finalNodeIP = address
//				}
//			}
		}
	}
	fmt.Println("FinalNodeIP is %v", finalNodeIP)
}

type TailscaleOutput struct {
    TailscaleIPs []string `json:"TailscaleIPs"`
}

func tailScaleExec() {
	cmd := exec.Command("tailscale", "status", "--json")
	var out bytes.Buffer
        cmd.Stdout = &out
	err := cmd.Run()
	if err != nil {
		fmt.Println(err)
	}
	var tailscaleOutput TailscaleOutput
	json.Unmarshal([]byte(out.String()), &tailscaleOutput)
	fmt.Println("These are the local IPs: ", tailscaleOutput)
	for _,address := range(tailscaleOutput.TailscaleIPs){
		fmt.Println(address)
	}
}

func main() {
	tailScaleExec()
}

