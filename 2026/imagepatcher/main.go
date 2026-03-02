package main

import (
	"log"
	"time"

	"github.com/manuelbuil/PoCs/2026/imagepatcher/internal/kube"
)

const checkInterval = 2 * time.Minute

func checkForNewerImage() {
	imageName, _, imageErr := kube.GetTraefikImageFromKubeAPI()
	if imageErr != nil {
		log.Printf("failed to get current Traefik image: %v", imageErr)
	}

	behind, currentTag, latestTags, err := kube.GetTraefikTagsBehind()
	if err != nil {
		if behind == -1 && len(latestTags) > 0 {
			log.Printf("newer Traefik image likely available: current tag %q is older than latest observed tags %v", currentTag, latestTags)
			if imageErr == nil {
				written, filePath, writeErr := kube.WriteHelmChartConfigIfEnabled(imageName, latestTags[0])
				if writeErr != nil {
					log.Printf("failed to write HelmChartConfig: %v", writeErr)
				} else if written {
					log.Printf("wrote HelmChartConfig to %s using image %q:%s", filePath, imageName, latestTags[0])
				}
			}
			return
		}

		log.Printf("failed to check Traefik image freshness: %v", err)
		return
	}

	if behind > 0 {
		log.Printf("newer Traefik image available: current tag %q is %d tag(s) behind latest (%q)", currentTag, behind, latestTags[0])
		if imageErr == nil {
			written, filePath, writeErr := kube.WriteHelmChartConfigIfEnabled(imageName, latestTags[0])
			if writeErr != nil {
				log.Printf("failed to write HelmChartConfig: %v", writeErr)
			} else if written {
				log.Printf("wrote HelmChartConfig to %s using image %q:%s", filePath, imageName, latestTags[0])
			}
		}
	}
}

func main() {
	log.Printf("starting Traefik image watcher (interval: %s)", checkInterval)

	checkForNewerImage()

	ticker := time.NewTicker(checkInterval)
	defer ticker.Stop()

	for range ticker.C {
		checkForNewerImage()
	}
}
