package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"log"

	"golang.org/x/tools/go/packages"
	"golang.org/x/tools/go/ssa"
	"golang.org/x/tools/go/ssa/ssautil"
)

func main() {
	// Load, parse, and type-check the whole program.
	cfg := packages.Config{Mode: packages.LoadAllSyntax}
	initial, err := packages.Load(&cfg, "fmt", "net/http")
	if err != nil {
		log.Fatal(err)
	}

	// Create SSA packages for well-typed packages and their dependencies.
	// prog, pkgs := ssautil.AllPackages(initial, ssa.PrintPackages|ssa.InstantiateGenerics)
	prog, pkgs := ssautil.AllPackages(initial, ssa.InstantiateGenerics)
	_ = pkgs

	cwd := getSsaPath()
	fmt.Printf("cwd: %s\n", cwd)

	// Build SSA code for the whole program.
	prog.Build()
	writeAllPkgSsa(ssautil.AllFunctions(prog), cwd)

	fmt.Println("done.")
}

func writeAllPkgSsa(xs map[*ssa.Function]bool, cwd string) {
	var wg sync.WaitGroup

	for x := range xs {
		wg.Go(func() { writeSsaToFile(x, cwd) })
	}

	wg.Wait()
}

func writeSsaToFile(x *ssa.Function, cwd string) {
	file := getFileToWriteTo(x, cwd)
	defer file.Close()
	writeToFile(x, file)
}

func writeToFile(x *ssa.Function, file *os.File) {
	w := bufio.NewWriter(file)
	_, err := x.WriteTo(w)
	check(err)
	w.Flush()
}

func getFileToWriteTo(x *ssa.Function, cwd string) *os.File {
	pkgname := strings.ReplaceAll(x.Name(), "/", "_")
	path := filepath.Join(cwd, pkgname)
	file, err := os.Create(path)
	check(err)
	return file
}

func getSsaPath() string {
	cwd := getCWD()
	x := filepath.Join(cwd, "out")
	check(os.MkdirAll(x, os.ModePerm))
	return x
}

func getCWD() string {
	cwd, err := os.Getwd()
	check(err)
	return cwd
}

func check(e error) {
	if e != nil {
		panic(e)
	}
}
