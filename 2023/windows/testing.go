//go:build windows
// +build windows

package main

import (
	"context"
	"fmt"
	"os/exec"
	"os"
	"time"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/eventlog"

)

// myHandler is a type that implements the svc.Handler interface
type myHandler struct{
    elog *eventlog.Log
}

func (m *myHandler) Execute(args []string, r <-chan svc.ChangeRequest, changes chan<- svc.Status) (ssec bool, errno uint32) {
	const cmdsAccepted = svc.AcceptStop | svc.AcceptShutdown

	changes <- svc.Status{State: svc.StartPending}

	// Start your service logic here
	go runServiceLogic(changes, *m.elog)

	changes <- svc.Status{State: svc.Running, Accepts: cmdsAccepted}

	for {
		select {
		case c := <-r:
			switch c.Cmd {
			case svc.Interrogate:
				changes <- c.CurrentStatus
			case svc.Stop, svc.Shutdown:
				changes <- svc.Status{State: svc.StopPending}
				// Stop your service logic here
				stopServiceLogic(*m.elog)
				return false, 0
			default:
				m.elog.Info(1, "Unexpected control request")
			}
		}
	}
}

func runServiceLogic(changes chan<- svc.Status, elog eventlog.Log) {
	elog.Info(2,"Inside runServiceLogic")
       	myPath := "C:\\var\\lib\\rancher\\rke2\\agent\\containerd\\"
	outputFile, err := os.Create(myPath + "fromService.log")
	if err != nil {
		elog.Error(1, fmt.Sprintf("Error creating log file: %v", err))
	}
	defer outputFile.Close()
	specificEnvs := []string{fmt.Sprintf("PATH=%s;C:\\var\\lib\\rancher\\rke2\\data\\v1.27.4-rke2r1-windows-amd64-66ae4fa01104\\bin", os.Getenv("PATH"))}
        ctx := context.Background()
	time.Sleep(10 * time.Second)
        //cmd := exec.CommandContext(ctx, "powershell", "Get-ChildItem")
	command := "C:\\var\\lib\\rancher\\rke2\\data\\v1.27.4-rke2r1-windows-amd64-66ae4fa01104\\bin\\containerd"
        cmd := exec.CommandContext(ctx, command, "-c", "C:\\var\\lib\\rancher\\rke2\\agent\\etc\\containerd\\config.toml")
       	cmd.Stdout = outputFile
        cmd.Stderr = outputFile
        cmd.Env = specificEnvs
	elog.Info(2, fmt.Sprintf("These are the env: %v", specificEnvs))
	if err := cmd.Run(); err != nil {
		elog.Error(1, fmt.Sprintf("Error running the command: %v", err))
	}

// 	for {
        	// Replace this with your service logic
//		elog.Info(2, "HELLLLOOO!!!!")
//		time.Sleep(10 * time.Second)
//		elog.Info(3, "MY NAME IS MANUEL! ")
        	//cmd := exec.CommandContext(ctx, "containerd", "-c", "C:\\var\\lib\\rancher\\rke2\\agent\\etc\\containerd\\config.toml")
        	//cmd.Stdout = outputFile
        	//cmd.Stderr = outputFile
        	//if err := cmd.Run(); err != nil {
                //	elog.Info(3, err.Error())
        	//}
//	}
        elog.Info(1,"byeeee")
}

func stopServiceLogic(elog eventlog.Log) {
	// Implement any cleanup or shutdown logic here
	elog.Info(4, "Service is stopping...")
}

func main() {
	serviceName := "myService"
	el, _ := eventlog.Open(serviceName)
	defer el.Close()

	el.Info(5, "STARTING!")
	interactive, err := svc.IsAnInteractiveSession()
	if err != nil {
		el.Info(6, "Failed to determine if we are running in an interactive session")
	}
	if interactive {
		el.Info(7, "Service should not be run in an interactive session")
	}

	// Register the service
	err = svc.Run(serviceName, &myHandler{elog: el})
	if err != nil {
		el.Info(8, "Failed to start the service")
	}
}

