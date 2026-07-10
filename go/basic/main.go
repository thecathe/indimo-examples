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

	cwd := getCWD()
	fmt.Printf("cwd: %s\n", cwd)

	writeAllPkgSsa(pkgs, cwd, "ssa_pkgs")

	// Build SSA code for the whole program.
	prog.Build()
	writeAllPkgSsa(prog.AllPackages(), cwd, "all_pkgs")

	fmt.Println("done.")
}

func writeAllPkgSsa(ps []*ssa.Package, cwd string, prefix string) {
	var wg sync.WaitGroup

	for i, p := range ps {
		fmt.Printf("%s %d: %s\n", prefix, i, p.Pkg.Path())
		wg.Go(func() { writeSsaToFile(p, cwd, prefix) })
	}

	wg.Wait()
}

func writeSsaToFile(p *ssa.Package, cwd string, prefix string) {
	file := getFileToWriteTo(p, cwd, prefix)
	defer file.Close()
	writeToFile(p, file)
}

func writeToFile(p *ssa.Package, file *os.File) {
	w := bufio.NewWriter(file)
	_, err := p.WriteTo(w)
	check(err)
	w.Flush()
}

func getFileToWriteTo(p *ssa.Package, cwd string, prefix string) *os.File {
	pkgname := strings.Replace(p.Pkg.Path(), "/", "_", -1)
	filename := fmt.Sprintf("%s %s", prefix, pkgname)
	path := filepath.Join(cwd, filename)
	file, err := os.Create(path)
	check(err)
	return file
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
