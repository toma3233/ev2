// +gocover:ignore:file it is a temporary tool only used during the overlay.resource migration
package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "diff-aksbuilder",
	Short: "",
	Long:  "",
}

func init() {
	rootCmd.AddCommand(GetWorkspacesCMD())
	rootCmd.AddCommand(GetCheckCMD())
}

// This is a naive ad-hoc tool to compare the artifact ARM parameters between ev2ab and aksbuilder.
// Aksbuilder artifacts should contain the same parameters as ev2ab. (TODO: same resources in the template.)
func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Printf("Error: %s\n", err)
		fmt.Printf(`
========
Please check the published build artifacts difference between ev2ab and aksbuilder.
NOTE: The task is to check the ev2ab artifacts are a subset of aksbuilder artifacts for specific ARM template.
During the overlay.resource migration, please also update the ARM template onboarded to aksbuilder when you update an ARM template under the "ev2" folder.
The registered links between new and old overlay resources are in ev2/diff-aksbuilder/matrix.go.
If you still have questions, please feel free to tag Zhongyi Zhang (zhongz) for help.`)
		os.Exit(1)
	}
}
