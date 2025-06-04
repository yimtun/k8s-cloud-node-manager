package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"

	"k8s.io/client-go/tools/clientcmd"
)

func main() {
	flag.Usage = func() {
		fmt.Println("usage: kubectl restart <nodename>")
	}
	flag.Parse()
	if flag.NArg() != 1 {
		flag.Usage()
		os.Exit(1)
	}
	nodename := flag.Arg(0)

	kubeconfigPath := os.Getenv("KUBECONFIG")
	if kubeconfigPath == "" {
		kubeconfigPath = filepath.Join(os.Getenv("HOME"), ".kube", "config")
	}

	//  kubeconfig
	config, err := clientcmd.LoadFromFile(kubeconfigPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read kubeconfig err: %v\n", err)
		os.Exit(1)
	}

	//  context
	ctx := config.CurrentContext
	context := config.Contexts[ctx]
	cluster := config.Clusters[context.Cluster]
	user := config.AuthInfos[context.AuthInfo]

	// get  API Server
	apiServer := cluster.Server

	//  CA
	caData, err := decodeOrRead(cluster.CertificateAuthorityData, cluster.CertificateAuthority)
	if err != nil {
		fmt.Fprintf(os.Stderr, "CA : %v\n", err)
		os.Exit(1)
	}

	//  CA
	caPool := x509.NewCertPool()
	if !caPool.AppendCertsFromPEM(caData) {
		fmt.Fprintf(os.Stderr, "add CA err\n")
		os.Exit(1)
	}

	//  TLS
	tlsConfig := &tls.Config{
		RootCAs: caPool,
	}

	var bearerToken string

	//
	if user.Token != "" {
		//  Token
		fmt.Fprintf(os.Stderr, "use Token\n")
	} else if user.Exec != nil {
		// 支持 exec 认证（如 aws eks get-token）
		fmt.Fprintf(os.Stderr, "use exec : %s %v\n", user.Exec.Command, user.Exec.Args)
		cmdArgs := append([]string{user.Exec.Command}, user.Exec.Args...)
		cmd := exec.Command(cmdArgs[0], cmdArgs[1:]...)
		//  env
		cmd.Env = os.Environ()
		for _, env := range user.Exec.Env {
			cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", env.Name, env.Value))
		}
		out, err := cmd.Output()
		if err != nil {
			fmt.Fprintf(os.Stderr, "exec fail: %v\n", err)
			os.Exit(1)
		}
		// get  .status.token
		var execResult struct {
			Status struct {
				Token string `json:"token"`
			} `json:"status"`
		}
		if err := json.Unmarshal(out, &execResult); err != nil {
			fmt.Fprintf(os.Stderr, " exec err: %v\n", err)
			os.Exit(1)
		}
		bearerToken = execResult.Status.Token
	} else {
		//
		//fmt.Fprintf(os.Stderr, "xx\n")
		certData, err := decodeOrRead(user.ClientCertificateData, user.ClientCertificate)
		if err != nil {
			fmt.Fprintf(os.Stderr, "err: %v\n", err)
			os.Exit(1)
		}

		keyData, err := decodeOrRead(user.ClientKeyData, user.ClientKey)
		if err != nil {
			fmt.Fprintf(os.Stderr, "err: %v\n", err)
			os.Exit(1)
		}

		cert, err := tls.X509KeyPair(certData, keyData)
		if err != nil {
			fmt.Fprintf(os.Stderr, "err: %v\n", err)
			os.Exit(1)
		}
		tlsConfig.Certificates = []tls.Certificate{cert}
	}

	//
	tr := &http.Transport{TLSClientConfig: tlsConfig}
	client := &http.Client{Transport: tr}

	//
	url := fmt.Sprintf("%s/apis/infraops.michael.io/v1/nodes/%s/restart", apiServer, nodename)
	req, err := http.NewRequest("POST", url, nil)
	if err != nil {
		fmt.Fprintf(os.Stderr, "err: %v\n", err)
		os.Exit(1)
	}

	//
	if user.Token != "" {
		req.Header.Set("Authorization", "Bearer "+user.Token)
	}

	//
	if bearerToken != "" {
		req.Header.Set("Authorization", "Bearer "+bearerToken)
	}

	//
	resp, err := client.Do(req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "err: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	//
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Fprintf(os.Stderr, "err: %v\n", err)
		os.Exit(1)
	}

	//
	if resp.StatusCode != http.StatusOK {
		fmt.Fprintf(os.Stderr, "err: %d，resp: %s\n", resp.StatusCode, string(body))
		os.Exit(1)
	}

	fmt.Printf("%s\n", body)
}

// decodeOrRead   base64
func decodeOrRead(data []byte, file string) ([]byte, error) {
	if len(data) > 0 {
		return data, nil
	}
	if file != "" {
		return ioutil.ReadFile(file)
	}
	return nil, fmt.Errorf("err")
}
