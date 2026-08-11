package jssatest

import "log"

func main() {
	jssatestmain()
}

type R struct {
	X int
	Y int
}

func jssatestmain() {
	x := 1
	r := new_r(x)

	c := make(chan R)
	s := make(chan int, 1)
	go consumer(c, s)

	c <- r
	n := <-s
	log.Printf("from %v to %d\n", r, n)
}

func consumer(c <-chan R, s chan<- int) {
	q := <-c
	q = r_incr(q)
	sum := r_sum(q)
	s <- sum
}

func new_r(x int) R {
	if x > 0 {
		return R{
			X: x, Y: -x,
		}
	} else {
		return R{
			X: x, Y: 0,
		}
	}
}

func r_incr(x R) R {
	return R{
		X: x.X + 1, Y: x.Y + 1,
	}
}

func r_sum(x R) int {
	return x.X + x.Y
}
