package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

func checkResources(ev2abFolder, aksbuilderFolder, region, templateName string) error {
	ev2abResources, err := getResources(ev2abFolder, region, templateName)
	if err != nil {
		return fmt.Errorf("get ev2abResources err: %s", err)
	}
	aksbuilderResources, err := getResources(aksbuilderFolder, region, templateName)
	if err != nil {
		return fmt.Errorf("get aksbuilderResources err: %s", err)
	}

	debugInfo := fmt.Sprintf("debugInfo:\n ev2ab: %s\n aksbuilder: %s\n", ev2abResources, aksbuilderResources)
	if len(ev2abResources) != len(aksbuilderResources) {
		return fmt.Errorf("diff resources: ev2ab length[%d] / aksbuilder: length[%d]\n %s", len(ev2abResources), len(aksbuilderResources), debugInfo)
	}
	for k, ev2abV := range ev2abResources {
		byteEv2abV, err := json.Marshal(ev2abV)
		if err != nil {
			return fmt.Errorf("marshal ev2ab resource err: %s", err)
		}
		byteAksbuilderV, err := json.Marshal(aksbuilderResources[k])
		if err != nil {
			return fmt.Errorf("marshal aksbuilder resource err: %s", err)
		}
		if string(byteEv2abV) != string(byteAksbuilderV) {
			return fmt.Errorf("diff resource - ev2ab: [%s] / aksbuilder: [%s]\n %s", string(byteEv2abV), string(byteAksbuilderV), debugInfo)
		}
	}
	return nil
}

func getResources(dir string, region string, templateName string) ([]interface{}, error) {
	templateFile := fmt.Sprintf("%s.Template.json", templateName)
	templateByte, err := os.ReadFile(filepath.Join(dir, "Templates", templateFile))
	if err != nil {
		return nil, fmt.Errorf("read template err: %s", err)
	}
	template := map[string]interface{}{}
	err = json.Unmarshal(templateByte, &template)
	if err != nil {
		return nil, fmt.Errorf("unmarshal template err: %s", err)
	}
	resources := template["resources"].([]interface{})
	return resources, nil
}
