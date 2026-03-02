package main

import (
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/manuelbuil/PoCs/2026/rke2-patcher/internal/components"
	"github.com/manuelbuil/PoCs/2026/rke2-patcher/internal/cve"
	"github.com/manuelbuil/PoCs/2026/rke2-patcher/internal/dockerhub"
	"github.com/manuelbuil/PoCs/2026/rke2-patcher/internal/kube"
	"github.com/manuelbuil/PoCs/2026/rke2-patcher/internal/patcher"
)

const version = "0.1.0"

func main() {
	log.SetFlags(0)

	if len(os.Args) == 2 && strings.TrimSpace(os.Args[1]) == "--version" {
		printVersion()
		return
	}

	if len(os.Args) < 3 {
		printUsage()
		os.Exit(2)
	}

	command := strings.TrimSpace(os.Args[1])
	componentName := strings.TrimSpace(os.Args[2])
	extraArgs := os.Args[3:]

	component, err := components.Resolve(componentName)
	if err != nil {
		log.Printf("%v", err)
		printUsage()
		os.Exit(2)
	}

	switch command {
	case "image-cve":
		if len(extraArgs) > 0 {
			log.Printf("unexpected extra arguments for %q", command)
			printUsage()
			os.Exit(2)
		}
		if err := runCVE(component); err != nil {
			log.Fatal(err)
		}
	case "image-list":
		if len(extraArgs) > 0 {
			log.Printf("unexpected extra arguments for %q", command)
			printUsage()
			os.Exit(2)
		}
		if err := runImageList(component); err != nil {
			log.Fatal(err)
		}
	case "image-patch":
		dryRun, parseErr := parseImagePatchOptions(extraArgs)
		if parseErr != nil {
			log.Printf("%v", parseErr)
			printUsage()
			os.Exit(2)
		}

		if err := runImagePatch(component, dryRun); err != nil {
			log.Fatal(err)
		}
	default:
		log.Printf("unsupported command %q", command)
		printUsage()
		os.Exit(2)
	}
}

func parseImagePatchOptions(args []string) (bool, error) {
	if len(args) == 0 {
		return false, nil
	}

	if len(args) == 1 && strings.TrimSpace(args[0]) == "--dry-run" {
		return true, nil
	}

	return false, fmt.Errorf("unsupported image-patch option(s): %s", strings.Join(args, " "))
}

func runCVE(component components.Component) error {
	if err := kube.EnsureAnyWorkloadExists(component.Workloads); err != nil {
		return err
	}

	runningImages, err := kube.ListRunningImagesByRepository(component.DockerHubRepository)
	if err != nil {
		return err
	}

	image := runningImages[0].Image
	result, err := cve.ListForImage(image)
	if err != nil {
		return fmt.Errorf("failed to scan image %q: %w", image, err)
	}

	fmt.Printf("component: %s\n", component.Name)
	fmt.Printf("image: %s\n", image)
	fmt.Printf("scanner: %s\n", result.Tool)

	if len(result.CVEs) == 0 {
		fmt.Println("CVEs: none")
		return nil
	}

	fmt.Printf("CVEs (%d):\n", len(result.CVEs))
	for _, id := range result.CVEs {
		fmt.Printf("- %s\n", id)
	}

	return nil
}

func runImageList(component components.Component) error {
	runningImages, err := kube.ListRunningImagesByRepository(component.DockerHubRepository)
	if err != nil {
		return fmt.Errorf("running image unavailable: %w", err)
	}

	tags, err := dockerhub.ListTags(component.DockerHubRepository, 20)
	if err != nil {
		return err
	}

	inUseTags := make(map[string]struct{})
	for _, summary := range runningImages {
		_, tag := kube.SplitImage(summary.Image)
		if tag != "" {
			inUseTags[tag] = struct{}{}
		}
	}

	fmt.Printf("component: %s\n", component.Name)
	fmt.Printf("repository: %s\n", component.DockerHubRepository)
	fmt.Printf("running image(s):\n")
	for _, summary := range runningImages {
		fmt.Printf("- %s (pods: %d)\n", summary.Image, summary.Count)
	}
	fmt.Printf("available tags (%d):\n", len(tags))

	for _, tag := range tags {
		suffix := ""
		if _, found := inUseTags[tag.Name]; found {
			suffix = " <-- in use"
		}

		if !tag.LastUpdated.IsZero() {
			fmt.Printf("- %s (updated %s)%s\n", tag.Name, tag.LastUpdated.Format("2006-01-02T15:04:05Z07:00"), suffix)
			continue
		}

		fmt.Printf("- %s%s\n", tag.Name, suffix)
	}

	return nil
}

func runImagePatch(component components.Component, dryRun bool) error {
	if err := kube.EnsureAnyWorkloadExists(component.Workloads); err != nil {
		return err
	}

	runningImages, err := kube.ListRunningImagesByRepository(component.DockerHubRepository)
	if err != nil {
		return err
	}

	runningImage := runningImages[0].Image
	currentImageName, currentImageTag := kube.SplitImage(runningImage)

	latestTag, err := dockerhub.LatestTag(component.DockerHubRepository)
	if err != nil {
		return err
	}

	if err := ensurePatchTargetIsNewer(component.DockerHubRepository, currentImageTag, latestTag.Name); err != nil {
		return err
	}

	if dryRun {
		filePath, content := patcher.BuildHelmChartConfig(component.Name, component.HelmChartConfigName, currentImageName, latestTag.Name)

		fmt.Printf("component: %s\n", component.Name)
		fmt.Printf("current image: %s\n", runningImage)
		fmt.Printf("current tag: %s\n", currentImageTag)
		fmt.Printf("new tag: %s\n", latestTag.Name)
		fmt.Printf("dry-run: true\n")
		fmt.Printf("would write HelmChartConfig: %s\n", filePath)
		fmt.Println("---")
		fmt.Print(content)

		return nil
	}

	filePath, err := patcher.WriteHelmChartConfig(component.Name, component.HelmChartConfigName, currentImageName, latestTag.Name)
	if err != nil {
		return err
	}

	fmt.Printf("component: %s\n", component.Name)
	fmt.Printf("current image: %s\n", runningImage)
	fmt.Printf("current tag: %s\n", currentImageTag)
	fmt.Printf("new tag: %s\n", latestTag.Name)
	fmt.Printf("wrote HelmChartConfig: %s\n", filePath)

	return nil
}

func ensurePatchTargetIsNewer(repository string, currentTag string, targetTag string) error {
	if strings.TrimSpace(currentTag) == strings.TrimSpace(targetTag) {
		return fmt.Errorf("refusing to patch: current tag %q is already the latest", currentTag)
	}

	tags, err := dockerhub.ListTags(repository, 200)
	if err != nil {
		return fmt.Errorf("failed to verify tag freshness: %w", err)
	}

	currentIndex := -1
	targetIndex := -1
	for index, tag := range tags {
		if tag.Name == currentTag && currentIndex == -1 {
			currentIndex = index
		}

		if tag.Name == targetTag && targetIndex == -1 {
			targetIndex = index
		}
	}

	if targetIndex == -1 {
		return fmt.Errorf("refusing to patch: target tag %q not found in latest observed tags", targetTag)
	}

	if currentIndex == -1 {
		return fmt.Errorf("refusing to patch: current tag %q not found in latest observed tags; cannot prove target is newer", currentTag)
	}

	if targetIndex >= currentIndex {
		return fmt.Errorf("refusing to patch: target tag %q is not newer than current tag %q", targetTag, currentTag)
	}

	return nil
}

func printUsage() {
	fmt.Println("Usage:")
	fmt.Println("  rke2-patcher --version")
	fmt.Println("  rke2-patcher image-cve <component>")
	fmt.Println("  rke2-patcher image-list <component>")
	fmt.Println("  rke2-patcher image-patch <component>")
	fmt.Println("  rke2-patcher image-patch <component> --dry-run")
	fmt.Println()
	fmt.Printf("Supported components: %s\n", strings.Join(components.Supported(), ", "))
}

func printVersion() {
	fmt.Printf("rke2-patcher %s\n", version)
}
