package main

import (
	"fmt"
	"os"
	"strconv"
)

func producer(r chan struct{}, rate_p int) {
	fmt.Printf("[producer] rate %v\n", rate_p)
	for {
		for range rate_p {
			r <- struct{}{}
		}
	}
}

func consumer(r chan struct{}, rate_c int) {
	fmt.Printf("[consumer] with rate %v\n", rate_c)
	for {
		for range rate_c {
			<-r
		}
	}
}

func Rates(num_p int, rate_p int, rate_c int, bound int) {
	// return channel
	fmt.Printf("[main] return channel bound by %v\n", bound)
	r := make(chan struct{}, bound)
	// make producers
	fmt.Printf("[main] making %v producers\n", num_p)
	for range num_p {
		go producer(r, rate_p)
	}
	// continue as consumer
	fmt.Printf("[main] continuing as consumer\n")
	consumer(r, rate_c)
}

func main() {
	num_p, rate_p, rate_c, bound := get_args()
	safe_args(num_p, rate_p, rate_c, bound)
	Rates(num_p, rate_p, rate_c, bound)
}

///////////////////////////////////////////////////////////////////////////////

/*
	below is for parsing input args from terminal, and printing out invariant prediction
*/

func safe_args(num_p int, rate_p int, rate_c int, bound int) {
	s := "..."
	if (num_p * rate_p) <= rate_c {
		s = "safe"
	} else {
		s = fmt.Sprintf("unsafe (throttling will begin after %v iterations of the consumer)", (float32(rate_c)/float32(num_p*rate_p))*float32(bound))
	}
	fmt.Printf("((%v * %v) <= %v) appears to be %v\n", num_p, rate_p, rate_c, s)
}

func err_args() string {
	return fmt.Sprintf("Unrecognised input: %v\nExpects 4 integer arguments:\n\t(1) number of producers\n\t(2) rate of producers\n\t(3) rate of consumer\n\t(4) bound of return channel\n", os.Args[1:])
}

func get_args() (int, int, int, int) {
	if len(os.Args) != 5 {
		panic(err_args())
	} else {
		return get_int(os.Args[1]), get_int(os.Args[2]), get_int(os.Args[3]), get_int(os.Args[4])
	}
}

func get_int(x string) int {
	i, err := strconv.Atoi(x)
	if err != nil {
		panic(err)
	}
	return i
}
