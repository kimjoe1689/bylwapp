package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/kimjoe1689/bylwapp/server/devicesim"
)

func main() {
	server := flag.String("server", "http://127.0.0.1:8080", "server base URL")
	token := flag.String("token", "", "collector device token")
	device := flag.String("device", "phone-1", "collector device id")
	scenario := flag.String("scenario", "nominal", "nominal, duplicate, outage, timeout, skew")
	flag.Parse()
	if *token == "" {
		fmt.Fprintln(os.Stderr, "device-sim rehearses sync faults. It does not produce thesis results.")
		fmt.Fprintln(os.Stderr, "usage: device-sim -token TOKEN [-scenario nominal|duplicate|outage|timeout|skew]")
		os.Exit(2)
	}
	journal := &devicesim.Journal{}
	eventID := "sim-" + *scenario
	skew := time.Duration(0)
	if *scenario == "skew" {
		skew = 6 * time.Hour
	}
	event, err := devicesim.SampleBloodPressure(*device, eventID, skew)
	if err != nil {
		fatal(err)
	}
	if _, err := journal.Add(event); err != nil {
		fatal(err)
	}
	gateway := devicesim.HTTPGateway{BaseURL: *server, Token: *token}
	switch *scenario {
	case "outage":
		gateway.NetworkDown = true
	case "timeout":
		gateway.DropReply = true
	case "duplicate":
		if err := devicesim.SyncOnce(context.Background(), journal, gateway); err != nil {
			fatal(err)
		}
		journal.Records[0].State = devicesim.StatePending
	case "nominal", "skew":
	default:
		fatal(fmt.Errorf("unknown scenario %s", *scenario))
	}
	if err := devicesim.SyncOnce(context.Background(), journal, gateway); err != nil {
		fatal(err)
	}
	for _, record := range journal.Records {
		fmt.Printf("%s %s attempts=%d %s\n", record.Event.EventID, record.State, record.Attempts, record.LastError)
	}
	fmt.Println("rehearsal only; do not copy these lines into Chapter 4")
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
