// +gocover:ignore:file it is a temporary tool only used during the overlay.resource migration
package main

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
)

type ARMTemplate struct {
	Name                string `json:"name"`
	AksbuilderWorkspace string `json:"aksbuilderWorkspace"`
	AksbuilderEv2Name   string `json:"aksbuilderEv2Name"`
	Ev2abTarget         string `json:"ev2abTarget"`
}

var matrix = []ARMTemplate{
	/*
		{
			Name:                "flt",
			AksbuilderWorkspace: "fleet",
			AksbuilderEv2Name:   "fleet-regionresources.gotemplate.ev2",
			Ev2abTarget:         "overlay.resource.region",
			// Said, the rendered fleet/resources/region/Parameters/flt.Parameters.json
			//   should include all the parameters in the rendered overlay.resource.region/Parameters/flt.Parameters.json.
		},
	*/
}

func GetWorkspacesCMD() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "workspaces",
		Short: "expose the workspaces to be built by aksbuilder",
		Long:  "expose the workspaces to be built by aksbuilder",
		RunE: func(command *cobra.Command, args []string) error {
			workspaces := make([]string, len(matrix))
			for i, v := range matrix {
				workspaces[i] = v.AksbuilderWorkspace
			}
			fmt.Println(strings.Join(workspaces[:], ","))
			return nil
		},
	}
	return cmd
}
