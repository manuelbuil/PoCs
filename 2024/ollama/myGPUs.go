package main

import (
	"fmt"
	"log"

	"github.com/NVIDIA/go-nvml/pkg/nvml"
)

func main() {
	ret := nvml.Init()
	if ret != nvml.SUCCESS {
		log.Fatalf("Unable to initialize NVML: %v", nvml.ErrorString(ret))
	}
	defer func() {
		ret := nvml.Shutdown()
		if ret != nvml.SUCCESS {
			log.Fatalf("Unable to shutdown NVML: %v", nvml.ErrorString(ret))
		}
	}()

	count, ret := nvml.DeviceGetCount()
	if ret != nvml.SUCCESS {
		log.Fatalf("Unable to get device count: %v", nvml.ErrorString(ret))
	}

        for i:= 0; i < count; i++ {
                device, ret:= nvml.DeviceGetHandleByIndex(i)
                if ret!= nvml.SUCCESS {
                        log.Fatalf("Unable to get device at index %d: %v", i, nvml.ErrorString(ret))
                }

                uuid, ret:= device.GetUUID()
                if ret!= nvml.SUCCESS {
                        log.Fatalf("Unable to get uuid of device at index %d: %v", i, nvml.ErrorString(ret))
                }

                fmt.Printf("Device %d UUID: %v\n", i, uuid)

                driverVersion, ret:= nvml.SystemGetDriverVersion() // Get driver version
                if ret!= nvml.SUCCESS {
                        log.Printf("Unable to get driver version for device %d: %v", i, nvml.ErrorString(ret)) // Print but don't exit
                } else {
                                fmt.Printf("Device %d Driver Version: %v\n", i, driverVersion)
                }

                major, minor, ret:= device.GetCudaComputeCapability() // Get major and minor version
                if ret!= nvml.SUCCESS {
                        log.Printf("Unable to get CUDA version for device %d: %v", i, nvml.ErrorString(ret))
                } else {
                        fmt.Printf("Device %d CUDA Compute Capability: Major: %d, Minor: %d\n", i, major, minor)
                }

                name, ret:= device.GetName() // Get the name of the GPU
                if ret!= nvml.SUCCESS {
                        log.Printf("Unable to get the name of the device %d: %v", i, nvml.ErrorString(ret))
                } else {
                        fmt.Printf("Device %d Name: %s\n", i, name)
                }
		brand, ret:= device.GetBrand()
		if ret!= nvml.SUCCESS {
		    log.Printf("Unable to get the brand of the device %d: %v", i, nvml.ErrorString(ret))
		} else {
		    brandName:= ""
		    switch brand {
		    case nvml.BRAND_UNKNOWN:
		        brandName = "Unknown"
		    case nvml.BRAND_NVIDIA:
		        brandName = "NVIDIA"
		    case nvml.BRAND_QUADRO:
		        brandName = "Quadro"
		    case nvml.BRAND_TESLA:
		        brandName = "Tesla"
		    case nvml.BRAND_GRID:
		        brandName = "Grid"
    		}
		fmt.Printf("Device %d Brand: %s\n", i, brandName)
		}
        }
}

