// +gocover:ignore:file it is a temporary tool only used during the overlay.resource migration
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func checkParameters(ev2abFolder, aksbuilderFolder, region, templateName string) error {
	ev2abParameters, err := getParameters(ev2abFolder, region, templateName, true)
	if err != nil {
		return fmt.Errorf("get ev2abParameters err: %s", err)
	}
	aksbuilderParameters, err := getParameters(aksbuilderFolder, region, templateName, false)
	if err != nil {
		return fmt.Errorf("get aksbuilderParameters err: %s", err)
	}

	debugInfo := fmt.Sprintf("debugInfo:\n ev2ab: %s\n aksbuilder: %s\n", ev2abParameters, aksbuilderParameters)
	for k, ev2abV := range ev2abParameters {
		if aksbuilderV, ok := aksbuilderParameters[k]; ok {
			v1 := ev2abV.(map[string]interface{})["value"].(string)
			v2 := aksbuilderV.(map[string]interface{})["value"].(string)
			if v1 != v2 {
				return fmt.Errorf("diff parameter: %s - ev2ab: [%s] / aksbuilder: [%s]\n %s", k, v1, v2, debugInfo)
			}
		} else {
			return fmt.Errorf("aksbuilder artifacts missing parameter: %s\n %s", k, debugInfo)
		}
	}
	return nil
}

func getParameters(dir string, region string, templateName string, isEv2ab bool) (map[string]interface{}, error) {
	var parametersFile string
	if isEv2ab {
		parametersFile = fmt.Sprintf("%s.%s.Parameters.json", region, templateName)
	} else {
		parametersFile = fmt.Sprintf("%s.Parameters.json", templateName)
	}
	parametersByte, err := os.ReadFile(filepath.Join(dir, "Parameters", parametersFile))
	if err != nil {
		return nil, fmt.Errorf("read parameters err: %s", err)
	}
	parameters := map[string]interface{}{}
	err = json.Unmarshal(parametersByte, &parameters)
	if err != nil {
		return nil, fmt.Errorf("unmarshal parameters err: %s", err)
	}
	parameters = parameters["parameters"].(map[string]interface{})

	scopeBindingsFile := fmt.Sprintf("%s.ScopeBindings.json", region)
	scopeBindingsBytes, err := os.ReadFile(filepath.Join(dir, scopeBindingsFile))
	if err != nil {
		return nil, fmt.Errorf("read scopeBindings err: %s", err)
	}
	scopeBindings := map[string]interface{}{}
	err = json.Unmarshal(scopeBindingsBytes, &scopeBindings)
	if err != nil {
		return nil, fmt.Errorf("unmarshal scopeBindings err: %s", err)
	}
	iScopeBindings := scopeBindings["scopeBindings"].([]interface{})

	for _, scopeBinding := range iScopeBindings {
		scopeBinding := scopeBinding.(map[string]interface{})

		var cdt bool
		if isEv2ab {
			cdt = scopeBinding["scopeTagName"] == "region" || scopeBinding["scopeTagName"] == "ev2ab.system"
		} else {
			cdt = scopeBinding["scopeTagName"] == "ResourceTag"
		}
		if cdt {
			for _, binding := range scopeBinding["bindings"].([]interface{}) {
				binding := binding.(map[string]interface{})
				find := binding["find"].(string)
				replaceWith := binding["replaceWith"].(string)

				for k, v := range parameters {
					replacedV := v.(map[string]interface{})
					if value, ok := replacedV["value"].(string); ok {
						replacedV["value"] = strings.ReplaceAll(value, find, replaceWith)
						parameters[k] = replacedV
					}
				}
			}
		}
	}
	return parameters, nil
}
