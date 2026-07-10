package main

import (
	"basic/jssa"
)

func main() {
	all := jssa.BuildAllSSA("./jssatest/...")
	jssa.WriteAllSSA(all)
}
