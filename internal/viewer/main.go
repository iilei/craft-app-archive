package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

func main() {
	root := flag.String("root", ".", "path to static website root")
	host := flag.String("host", "127.0.0.1", "bind host")
	port := flag.Int("port", 42420, "local port to serve on")
	noOpen := flag.Bool("no-open", false, "do not open browser automatically")
	flag.Parse()

	absRoot, err := filepath.Abs(*root)
	if err != nil {
		log.Fatal(err)
	}

	if _, err := os.Stat(absRoot); err != nil {
		log.Fatal("root does not exist: ", absRoot)
	}

	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir(absRoot)))

	addr := fmt.Sprintf("%s:%d", *host, *port)
	log.Printf("Serving %s at http://%s", absRoot, addr)

	if !*noOpen {
		openBrowser(fmt.Sprintf("http://%s", addr))
	}

	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

func openBrowser(url string) {
	var cmd *exec.Cmd

	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", "", url)
	case "linux":
		cmd = exec.Command("xdg-open", url)
	default:
		cmd = nil
	}

	if cmd != nil {
		if err := cmd.Run(); err != nil {
			log.Printf("browser launch failed: %v", err)
		}
	}
}
