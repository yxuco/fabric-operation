
all: clean build

build:
	cd src && go build -o ../gateway

run:
	CRYPTO_PATH=$(GOPATH)/src/github.com/hyperledger/fabric-samples/first-network/crypto-config ./gateway -logtostderr -v 2

codegen:
	protoc -I=./src \
		-I=$(GOPATH)/src/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis \
		--go_out=plugins=grpc:./src/fabric \
		./src/fabric.proto
	protoc -I=./src \
		-I=$(GOPATH)/src/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis \
		--grpc-gateway_out=logtostderr=true:./src/fabric \
		./src/fabric.proto
	protoc -I=./src \
		-I=$(GOPATH)/src/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis \
		--swagger_out=logtostderr=true:./swagger-ui \
		./src/fabric.proto

clean:
	rm -f gateway

depend:
	go get -u github.com/golang/protobuf/protoc-gen-go
	go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway
	go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger
