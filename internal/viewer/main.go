package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
)

func main() {
	root := flag.String("root", "", "path to static website root (default: dist/ next to launchers/)")
	host := flag.String("host", "127.0.0.1", "bind host: 127.0.0.1 or localhost")
	port := flag.Int("port", 42420, "local port to serve on, 0-65535 (0 picks a free port)")
	noOpen := flag.Bool("no-open", false, "do not open browser automatically")
	flag.Parse()

	if *host != "127.0.0.1" && *host != "localhost" {
		log.Fatalf("host must be 127.0.0.1 or localhost, got %q", *host)
	}
	if *port < 0 || *port > 65535 {
		log.Fatalf("port must be between 0 and 65535, got %d", *port)
	}

	siteRoot := *root
	if siteRoot == "" {
		var err error
		if siteRoot, err = findSiteRoot(); err != nil {
			log.Fatal(err)
		}
	}
	absRoot, err := filepath.Abs(siteRoot)
	if err != nil {
		log.Fatal(err)
	}
	if info, err := os.Stat(absRoot); err != nil || !info.IsDir() {
		log.Fatal("root is not a directory: ", absRoot)
	}

	// Listen before opening the browser so the URL carries the real port,
	// including when --port 0 lets the OS choose one.
	ln, err := net.Listen("tcp", net.JoinHostPort(*host, strconv.Itoa(*port)))
	if err != nil {
		log.Fatal(err)
	}
	url := fmt.Sprintf("http://%s", ln.Addr())
	log.Printf("Serving %s at %s", absRoot, url)

	if !*noOpen {
		openBrowser(url)
	}

	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir(absRoot)))
	if err := http.Serve(ln, mux); err != nil {
		log.Fatal(err)
	}
}

// findSiteRoot looks for dist/ relative to the executable, which normally
// lives at <archive>/launchers/<target>/, then falls back to ./dist.
func findSiteRoot() (string, error) {
	var candidates []string
	if exe, err := os.Executable(); err == nil {
		if resolved, err := filepath.EvalSymlinks(exe); err == nil {
			exe = resolved
		}
		dir := filepath.Dir(exe)
		candidates = append(candidates,
			filepath.Join(dir, "..", "..", "dist"),
			filepath.Join(dir, "dist"),
		)
	}
	candidates = append(candidates, "dist")
	for _, c := range candidates {
		if info, err := os.Stat(c); err == nil && info.IsDir() {
			return c, nil
		}
	}
	return "", fmt.Errorf("no dist/ directory found (looked in %v); pass --root", candidates)
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
		if err := cmd.Start(); err != nil {
			log.Printf("browser launch failed: %v", err)
			return
		}
		go cmd.Wait() // reap the launcher process; the server keeps running
	}
}
