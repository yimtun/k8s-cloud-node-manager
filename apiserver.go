package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	aliyun "github.com/aliyun/alibaba-cloud-sdk-go/services/ecs"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/gorilla/mux"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	tcCommon "github.com/tencentcloud/tencentcloud-sdk-go/tencentcloud/common"
	tcProfile "github.com/tencentcloud/tencentcloud-sdk-go/tencentcloud/common/profile"
	tencent "github.com/tencentcloud/tencentcloud-sdk-go/tencentcloud/cvm/v20170312"
)

var kubeconfigPath string

func handleRestart(w http.ResponseWriter, r *http.Request) {
	fmt.Printf("restart vmi")
	vars := mux.Vars(r)
	//namespace := vars["namespace"]
	name := vars["name"]
	//
	//config, err := clientcmd.BuildConfigFromFlags("", filepath.Join(homedir.HomeDir(), ".kube", "config"))
	//if err != nil {
	//	log.Fatalf("Failed to build config: %v", err)
	//}
	//
	//clientset, err := kubernetes.NewForConfig(config)
	//if err != nil {
	//	log.Fatalf("Failed to create client: %v", err)
	//}
	//
	//vmi, err := clientset.CoreV1().Pods(namespace).Get(context.TODO(), name, metav1.GetOptions{})
	//if err != nil {
	//	fmt.Printf("get vmi err", err)
	//	http.Error(w, fmt.Sprintf("Error getting VMI: %v", err), http.StatusInternalServerError)
	//	return
	//}
	//
	//log.Printf("Restarting VMI: %s", vmi.Name)
	//
	//
	//err = clientset.CoreV1().Pods(namespace).Delete(context.TODO(), name, metav1.DeleteOptions{})
	//if err != nil {
	//	http.Error(w, fmt.Sprintf("Error restarting VMI: %v", err), http.StatusInternalServerError)
	//	return
	//}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "VMI %s has been restarted", name)
}

//func handlex(w http.ResponseWriter, r *http.Request) {
//	//
//	w.WriteHeader(http.StatusOK)
//	fmt.Fprintf(w, "VMI %s has been restarted")
//}

func handlex(w http.ResponseWriter, r *http.Request) {
	//  APIResourceList
	apiResourceList := map[string]interface{}{
		"kind":         "APIResourceList",
		"apiVersion":   "v1",
		"groupVersion": "infraops.michael.io/v1",
		"resources": []map[string]interface{}{
			{
				"name":         "nodes",
				"singularName": "node",
				"namespaced":   false,
				"kind":         "Node",
				"verbs": []string{
					"get",
					"list",
				},
			},
			{
				"name":         "nodes/restart",
				"singularName": "",
				"namespaced":   false,
				"kind":         "Node",
				"verbs": []string{
					"post",
				},
			},
		},
	}

	//  Content-Type
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	//
	json.NewEncoder(w).Encode(apiResourceList)
}

func init() {
	//  init
	flag.StringVar(&kubeconfigPath, "kubeconfig", "", "Path to kubeconfig file")
}

func main() {
	//
	flag.Parse()

	//fmt.Printf("xx", os.Getenv("KUBECONFIG"))
	// KUBECONFIG，
	//if envKubeconfig := os.Getenv("KUBECONFIG"); envKubeconfig != "" {
	//	kubeconfigPath = envKubeconfig
	//}

	r := mux.NewRouter()

	//
	r.HandleFunc("/apis/infraops.michael.io/v1/nodes", handleListNodes).Methods("GET")
	r.HandleFunc("/apis/infraops.michael.io/v1/namespaces/{namespace}/virtualmachineinstances/{name}/restart", handleRestart).Methods("POST")

	r.HandleFunc("/apis/infraops.michael.io/v1/nodes/{nodename}/restart", handleRestartMultiCloud).Methods("POST")

	r.HandleFunc("/apis/infraops.michael.io/v1", handlex).Methods("GET")

	log.Println("Starting API server with HTTPS...")
	certFile, keyFile := getCertPaths()
	//  HTTPS
	//err := http.ListenAndServeTLS(":443", "tls.crt", "tls.key", r) //
	//err := http.ListenAndServeTLS(":443", "certs/tls.crt", "certs/tls.key", r) //
	err := http.ListenAndServeTLS(":443", certFile, keyFile, r) //

	if err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func getCertPaths() (string, string) {
	//  check if run in pod
	if _, err := os.Stat("/var/run/secrets/kubernetes.io/serviceaccount/token"); err == nil {
		//
		return "/etc/tls/tls.crt", "/etc/tls/tls.key"
	}
	//
	return "./certs/tls.crt", "./certs/tls.key"
}

func getTencentEndpoint() string {
	//
	if _, err := os.Stat("/var/run/secrets/kubernetes.io/serviceaccount/token"); err == nil {
		//in pod use  internal api
		return "cvm.internal.tencentcloudapi.com"
	}
	// public api
	return "cvm.tencentcloudapi.com"
}

func getKubeClient() (*kubernetes.Clientset, error) {
	var config *rest.Config
	var err error

	if os.Getenv("KUBERNETES_SERVICE_HOST") != "" {
		fmt.Printf(os.Getenv("KUBERNETES_SERVICE_HOST"))
		config, err = rest.InClusterConfig() // inCluster
	} else {

		if kubeconfigPath == "" {
			kubeconfigPath = filepath.Join(os.Getenv("HOME"), ".kube", "config")
			fmt.Printf(kubeconfigPath)
		}
		//kubeconfig := filepath.Join(os.Getenv("HOME"), ".kube", "config")
		//config, err = clientcmd.BuildConfigFromFlags("", kubeconfigPath)
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfigPath)
	}
	if err != nil {
		return nil, err
	}
	return kubernetes.NewForConfig(config)
}

func handleRestartMultiCloud(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	nodename := vars["nodename"]

	if nodename == os.Getenv("MY_NODE_NAME") {
		http.Error(w, "you can't reboot"+nodename+"because I run on it", http.StatusInternalServerError)
		return
	}

	clientset, err := getKubeClient()
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create k8s client: %v", err), http.StatusInternalServerError)
		return
	}

	//
	node, err := clientset.CoreV1().Nodes().Get(context.TODO(), nodename, metav1.GetOptions{})
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to get node %s: %v", nodename, err), http.StatusInternalServerError)
		return
	}
	providerID := node.Spec.ProviderID
	if providerID == "" {
		http.Error(w, "Node providerID is empty", http.StatusInternalServerError)
		return
	}
	parts := strings.Split(providerID, "/")
	instanceID := parts[len(parts)-1]

	var cloudType string
	var rebootErr error

	switch {
	case strings.HasPrefix(providerID, "aws://"):
		cloudType = "AWS"
		rebootErr = rebootAWS(instanceID)
	case strings.HasPrefix(providerID, "alicloud://"):
		cloudType = "Aliyun"
		rebootErr = rebootAliyun(instanceID)
	case strings.HasPrefix(providerID, "qcloud://"):
		zone := node.Labels["topology.com.tencent.cloud.csi.cbs/zone"] // ap-beijing-x

		region := ""
		if zone != "" {
			//  get region
			idx := strings.LastIndex(zone, "-")
			if idx > 0 {
				region = zone[:idx] // ap-beijing
			}
		}

		cloudType = "TencentCloud"
		rebootErr = rebootTencent(instanceID, region)
	default:
		http.Error(w, fmt.Sprintf("not support cloud provider: %s", providerID), http.StatusBadRequest)
		return
	}

	if rebootErr != nil {
		http.Error(w, fmt.Sprintf("restart  %s ins %s failure: %v", cloudType, instanceID, rebootErr), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "Node %s (providerID: %s, ins-ID: %s, cloud-provider: %s)  restarted", nodename, providerID, instanceID, cloudType)
}

// AWS  reboot
func rebootAWS(instanceID string) error {
	sess, err := session.NewSession()
	if err != nil {
		return err
	}
	ec2Client := ec2.New(sess)
	_, err = ec2Client.RebootInstances(&ec2.RebootInstancesInput{
		InstanceIds: []*string{aws.String(instanceID)},
	})
	return err
}

func rebootAliyun(instanceID string) error {
	region := ""    //
	accessKey := "" //
	secretKey := ""
	client, err := aliyun.NewClientWithAccessKey(region, accessKey, secretKey)
	if err != nil {
		return err
	}
	request := aliyun.CreateRebootInstanceRequest()
	request.InstanceId = instanceID
	_, err = client.RebootInstance(request)
	return err
}

func rebootTencent(instanceID string, region string) error {
	secretId := os.Getenv("TENCENTCLOUD_SECRET_ID")
	secretKey := os.Getenv("TENCENTCLOUD_SECRET_KEY")
	//region = os.Getenv("TENCENTCLOUD_REGION")

	credential := tcCommon.NewCredential(secretId, secretKey)
	cpf := tcProfile.NewClientProfile()
	//cpf.HttpProfile.Endpoint = "cvm.internal.tencentcloudapi.com" //  iner  Endpoint
	cpf.HttpProfile.Endpoint = getTencentEndpoint()

	client, err := tencent.NewClient(credential, region, cpf)
	if err != nil {
		return err
	}

	req := tencent.NewRebootInstancesRequest()

	force := true
	req.ForceReboot = &force

	req.InstanceIds = []*string{&instanceID}
	_, err = client.RebootInstances(req)
	return err
}

// AWS:  IRSA
func newAWSSession() (*session.Session, error) {
	return session.NewSession()
}

// RAM for ServiceAccount
func newAliyunClient() (*aliyun.Client, error) {
	region := os.Getenv("ALICLOUD_REGION_ID")
	accessKey := os.Getenv("ALICLOUD_ACCESS_KEY_ID")
	secretKey := os.Getenv("ALICLOUD_ACCESS_KEY_SECRET")
	return aliyun.NewClientWithAccessKey(region, accessKey, secretKey)
}

// CAM for ServiceAccount
func newTencentClient() (*tencent.Client, error) {
	secretId := os.Getenv("TENCENTCLOUD_SECRET_ID")
	secretKey := os.Getenv("TENCENTCLOUD_SECRET_KEY")
	region := os.Getenv("TENCENTCLOUD_REGION")
	credential := tcCommon.NewCredential(secretId, secretKey)
	cpf := tcProfile.NewClientProfile()
	return tencent.NewClient(credential, region, cpf)
}

type Node struct {
	Kind       string                 `json:"kind,omitempty"`
	APIVersion string                 `json:"apiVersion,omitempty"`
	Metadata   map[string]interface{} `json:"metadata,omitempty"`
	Spec       map[string]interface{} `json:"spec,omitempty"`
	Status     map[string]interface{} `json:"status,omitempty"`
	//
}

type NodeList struct {
	Kind       string `json:"kind"`
	APIVersion string `json:"apiVersion"`
	Items      []Node `json:"items"`
}

func handleListNodes(w http.ResponseWriter, r *http.Request) {
	clientset, err := getKubeClient()
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create k8s client: %v", err), http.StatusInternalServerError)
		return
	}

	//
	nodeList, err := clientset.CoreV1().Nodes().List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to list nodes: %v", err), http.StatusInternalServerError)
		return
	}

	var myNodes []Node
	for _, node := range nodeList.Items {
		myNode := Node{
			Kind:       "Node",
			APIVersion: "infraops.michael.io/v1",
			Metadata: map[string]interface{}{
				"name": node.Name,
				//
			},
			// Spec/Status
		}
		myNodes = append(myNodes, myNode)
	}

	myNodeList := NodeList{
		Kind:       "NodeList",
		APIVersion: "infraops.michael.io/v1",
		Items:      myNodes,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(myNodeList)
}
