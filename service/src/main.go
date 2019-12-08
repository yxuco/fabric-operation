// Command-line starter of the Fabric gateway service.
package main

import (
	"crypto/tls"
	"crypto/x509"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"os"
	"path"
	"strings"

	"github.com/golang/glog"

	"github.com/yxuco/fabric-operation/service/fabric"

	"github.com/grpc-ecosystem/grpc-gateway/runtime"
	context "golang.org/x/net/context"
	grpc "google.golang.org/grpc"
)

// Command-line args to be provided at start of the gateway service
var networkFile, matcherFile, channel, org, user, grpcPort, httpPort string
var useTLS bool

// Initial values of the command-line args
func init() {
	flag.StringVar(&networkFile, "network", "config_byfn.yaml", "Path of the blockchain network configuration file")
	flag.StringVar(&matcherFile, "matcher", "matchers_byfn.yaml", "Path of entity matcher file for blockchain network config")
	flag.StringVar(&channel, "channel", "mychannel", "ID of the default channel for chaincode transactions")
	flag.StringVar(&org, "org", "org1", "Name of the Fabric organization that this client connects to")
	flag.StringVar(&user, "user", "Admin", "Name of the Fabric user to execute transactions on this connection")
	flag.StringVar(&grpcPort, "grpcport", "8082", "gRPC service listen port, must be exposed by docker container")
	flag.StringVar(&httpPort, "httpport", "8081", "HTTP REST service listen port, must be exposed by docker container")
	flag.BoolVar(&useTLS, "tls", false, "Use HTTPS if true")
}

// check env variables, which overrides the commandline input
func envOverride() {
	if v, ok := os.LookupEnv("GRPC_PORT"); ok && v != "" {
		grpcPort = v
	}
	if v, ok := os.LookupEnv("HTTP_PORT"); ok && v != "" {
		httpPort = v
	}
	if v, ok := os.LookupEnv("NETWORK_FILE"); ok && v != "" {
		networkFile = v
	}
	if v, ok := os.LookupEnv("ENTITY_MATCHER_FILE"); ok {
		matcherFile = v
	}
	if v, ok := os.LookupEnv("CHANNEL_ID"); ok && v != "" {
		channel = v
	}
	if v, ok := os.LookupEnv("USER_NAME"); ok && v != "" {
		user = v
	}
	if v, ok := os.LookupEnv("ORG"); ok && v != "" {
		org = v
	}
	if v, ok := os.LookupEnv("TLS_ENABLED"); ok && v == "true" {
		useTLS = true
	}
}

// Starts gateway service that listens to both HTTP and gRPC service requests.
// Turn on verbose logging using option -v 2
// Log to stderr using option -logtostderr
// or log to specified file using option -log_dir="mylogfile"
func main() {
	// parse command-line args
	flag.Parse()

	if flag.Lookup("logtostderr").Value.String() != "true" {
		// Set folder for log files
		if flag.Lookup("log_dir").Value.String() == "" {
			flag.Lookup("log_dir").Value.Set("./log")
		}
		if err := os.MkdirAll(flag.Lookup("log_dir").Value.String(), 0777); err != nil {
			fmt.Printf("Error creating log folder %s: %+v\n", flag.Lookup("log_dir").Value.String(), err)
			flag.Lookup("logtostderr").Value.Set("true")
		}
	}
	envOverride()

	// Start the gRPC server in goroutine
	serveGrpc()

	// connect to Fabric network
	glog.Infof("Connecting to Fabric network with config: %s, channel: %s, user: %s, org: %s", networkFile, channel, user, org)
	fabric.SetConfig(networkFile, matcherFile, channel, user, org)
	fbClient, err := fabric.NewNetworkClient(networkFile, matcherFile, channel, user, org)
	if err != nil {
		glog.Errorf("Error connecting to Fabric network: %+v", err)
	} else {
		defer fbClient.Close()
	}

	// Start REST service and creating gRPC proxy connection
	run()
}

// Starts HTTP server and corresponding reverse proxy connection to the gRPC service.
func run() error {
	glog.Info("Creating proxy connection to gRPC service")
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	gw := runtime.NewServeMux()
	opts := []grpc.DialOption{grpc.WithInsecure()}
	if err := fabric.RegisterGatewayHandlerFromEndpoint(ctx, gw, fmt.Sprintf("%s:%s", "localhost", grpcPort), opts); err != nil {
		glog.Error(err)
		panic(err)
	}

	glog.Info("Starting REST service on port:", httpPort)
	mux := http.NewServeMux()
	mux.HandleFunc("/swagger/", serveSwagger)
	mux.HandleFunc("/doc/", serveDoc)

	// Route REST service calls
	mux.Handle("/v1/", gw)
	if useTLS {
		glog.Info("Using TLS option")
		// First read the certificate
		clientCert, err := ioutil.ReadFile("cacert.pem")
		if err != nil {
			log.Fatal(err)
			panic(err)
		}
		certPool := x509.NewCertPool()
		if ok := certPool.AppendCertsFromPEM(clientCert); !ok {
			log.Fatalln("Unable to add certificate to certificate pool")
			panic("Unable to add certificate to certificate pool")
		}

		// Create the tlsConfig
		tlsConfig := &tls.Config{
			ClientAuth: tls.RequireAndVerifyClientCert,
			ClientCAs:  certPool,
			// Force it server side
			PreferServerCipherSuites: true,
			// TLS 1.2
			MinVersion: tls.VersionTLS12,
		}
		tlsConfig.BuildNameToCertificate()
		// Create a server
		httpServer := &http.Server{
			Addr:      fmt.Sprintf(":%s", httpPort),
			TLSConfig: tlsConfig,
			Handler:   mux,
		}

		return httpServer.ListenAndServeTLS("servercert.pem", "serverkey.pem")
	}
	return http.ListenAndServe(fmt.Sprintf(":%s", httpPort), mux)
}

// Starts gRPC service
// TODO: add TLS support
func serveGrpc() {
	glog.Info("Starting gRPC service on port:", grpcPort)
	// start listening for gRPC
	listen, err := net.Listen("tcp", ":"+grpcPort)
	if err != nil {
		glog.Error(err)
		panic(err)
	}
	// Instanciate new gRPC server
	server := grpc.NewServer()
	//register service
	fabric.RegisterGatewayServer(server, new(fabric.Service))

	// Start the gRPC server in goroutine
	go server.Serve(listen)
}

// Routes swagger-ui requests
func serveSwagger(w http.ResponseWriter, r *http.Request) {
	glog.V(2).Info("Received swagger request:", r.URL.Path)
	p := strings.TrimPrefix(r.URL.Path, "/swagger/")
	p = path.Join("swagger-ui/", p)
	http.ServeFile(w, r, p)
}

// Routes doc requests for gPRC API spec
func serveDoc(w http.ResponseWriter, r *http.Request) {
	glog.V(2).Info("Received doc request:", r.URL.Path)
	p := strings.TrimPrefix(r.URL.Path, "/doc/")
	p = path.Join("fabric.proto", p)
	http.ServeFile(w, r, p)
}
