package jssa

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"golang.org/x/tools/go/packages"
	"golang.org/x/tools/go/ssa"
	"golang.org/x/tools/go/ssa/ssautil"
)

type Instr struct {
	ID       string   `json:"id"`
	Block    int      `json:"block"`
	Kind     string   `json:"kind"`
	Operands []string `json:"operands"`
	Text     string   `json:"text"`
	Pos      int      `json:"pos"`
}

type Block struct {
	Index  int     `json:"index"`
	Succs  []int   `json:"succs"`
	Preds  []int   `json:"preds"`
	Instrs []Instr `json:"instrs"`
}

type Func struct {
	Name   string  `json:"name"`
	Blocks []Block `json:"blocks"`
}

func funcNames(xs []Func) []string {
	ys := make([]string, len(xs))
	for i, x := range xs {
		ys[i] = x.Name
	}
	return ys
}

func main() {
	funs := BuildAllSSA()
	log.Println("finished: BuildAllSSA")
	WriteAllSSA(funs)
	log.Println("finished: WriteAllSSA")
}

func BuildAllSSA(toLoad ...string) []Func {
	if toLoad == nil {
		toLoad = []string{"./..."}
	}
	log.Printf("toLoad: %v\n", toLoad)

	cfg := &packages.Config{Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles |
		packages.NeedImports | packages.NeedDeps | packages.NeedTypes |
		packages.NeedTypesSizes | packages.NeedSyntax | packages.NeedTypesInfo}

	initial, err := packages.Load(cfg, toLoad...)
	if err != nil {
		panic(err)
	}

	if packages.PrintErrors(initial) > 0 {
		panic("packages.Load reported errors, see above")
	}
	fmt.Printf("loaded %d package(s): ", len(initial))
	for _, p := range initial {
		fmt.Printf("%s ", p.PkgPath)
	}
	fmt.Println()

	prog, pkgs := ssautil.AllPackages(initial, 0)
	for i, p := range pkgs {
		if p == nil {
			log.Printf("SSA build FAILED for %s", initial[i].PkgPath)
		} else {
			log.Printf("SSA build OK for %s", p.Pkg.Path())
		}
	}
	prog.Build()

	fns := ssautil.AllFunctions(prog)

	// Pass 1: give every Value a stable, printable ID, so pass 2 can
	// reference operands by ID instead of embedding them (breaks cycles).
	ids := make(map[ssa.Value]string)
	preParseIds(fns, &ids)
	log.Println("finished: preParseIds")

	// Pass 2: build the actual records. Operands not in the ID map
	// (consts, globals, references to other functions) get inlined via
	// their own String() instead of an ID — they don't need referential
	// identity the way local register values do.
	rcs := buildFuncRecords(fns, ids)
	log.Println("finished: buildFuncRecords")

	log.Printf("built %d Func record(s): %v\n", len(rcs), funcNames(rcs)) // or just range and print .Name
	return rcs
}

func WriteAllSSA(xs []Func) {
	c := defaultWriteConfig()
	var wg sync.WaitGroup
	for _, x := range xs {
		wg.Go(func() { mapAndWrite(x, c) })
	}
	wg.Wait()
}

func mapAndWrite(x Func, c WriteConfig) {
	toWrite := funcToJson(x)
	file := getFileToWriteTo(x, c)
	defer file.Close()
	writeToFile(toWrite, file)
}

func funcToJson(x Func) []byte {
	if x, err := json.MarshalIndent(x, "", "  "); err == nil {
		return x
	} else {
		panic(err)
	}
}

func writeToFile(x []byte, file *os.File) {
	w := bufio.NewWriter(file)
	_, err := w.Write(x)
	check(err)
	w.Flush()
}

func getFileToWriteTo(x Func, c WriteConfig) *os.File {
	pkgname := strings.ReplaceAll(x.Name, "/", "|")
	filename := fmt.Sprintf("%s.%s", pkgname, c.Ext)
	path := filepath.Join(c.Cwd, filename)
	log.Printf("name: %s\n", filename)
	file, err := os.Create(path)
	check(err)
	return file
}

type WriteConfig struct {
	Cwd string
	Ext string
}

func defaultWriteConfig() WriteConfig {
	return WriteConfig{
		Cwd: getSSAPath(), Ext: "json",
	}
}

func getSSAPath() string {
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

// Pass 1: give every Value a stable, printable ID, so pass 2 can
// reference operands by ID instead of embedding them (breaks cycles).
func preParseIds(fns map[*ssa.Function]bool, ids *map[ssa.Value]string) {
	for fn := range fns {
		for bi, blk := range fn.Blocks {
			for ii, instr := range blk.Instrs {
				if v, ok := instr.(ssa.Value); ok {
					(*ids)[v] = fmt.Sprintf("%s:b%d:i%d", fn.Name(), bi, ii)
				}
			}
		}
		for pi, p := range fn.Params {
			(*ids)[p] = fmt.Sprintf("%s:param%d", fn.Name(), pi)
		}
		for fi, fv := range fn.FreeVars {
			(*ids)[fv] = fmt.Sprintf("%s:freevar%d", fn.Name(), fi)
		}
	}
}

// Pass 2: build the actual records. Operands not in the ID map
// (consts, globals, references to other functions) get inlined via
// their own String() instead of an ID — they don't need referential
// identity the way local register values do.
func buildFuncRecords(fns map[*ssa.Function]bool, ids map[ssa.Value]string) []Func {
	var out []Func
	for fn := range fns {
		f := Func{Name: fn.Name()}
		for bi, blk := range fn.Blocks {
			b := Block{Index: bi}
			for _, s := range blk.Succs {
				b.Succs = append(b.Succs, s.Index)
			}
			for _, p := range blk.Preds {
				b.Preds = append(b.Preds, p.Index)
			}
			for ii, instr := range blk.Instrs {
				rec := Instr{
					Block: bi,
					Kind:  fmt.Sprintf("%T", instr),
					Text:  instr.String(),
					Pos:   int(instr.Pos()),
				}
				if v, ok := instr.(ssa.Value); ok {
					rec.ID = ids[v]
				} else {
					rec.ID = fmt.Sprintf("%s:b%d:i%d", fn.Name(), bi, ii)
				}
				for _, opp := range instr.Operands(nil) {
					if opp == nil || *opp == nil {
						continue
					}
					if id, ok := ids[*opp]; ok {
						rec.Operands = append(rec.Operands, id)
					} else {
						rec.Operands = append(rec.Operands, (*opp).String())
					}
				}
				b.Instrs = append(b.Instrs, rec)
			}
			f.Blocks = append(f.Blocks, b)
		}
		out = append(out, f)
	}
	return out
}
