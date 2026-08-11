# Compiling Erlang

## Arguments for `erlc`



### Preprocessing

#### Preprocessed
```
erlc -P file.erl
``` 

#### Expanded macros
```
erlc -E file.erl
``` 


### To Core-Erlang

#### Raw Core-Erlang
```
erlc +to_core0 file.erl
``` 

#### With optimisations, e.g., inlining
```
erlc +to_core file.erl
``` 

#### No optimisations
```
erlc +to_core +no_copt file.erl
``` 


### Compilation


#### To Kernel Erlang
```
erlc +to_kernel file.erl
``` 

#### To BEAM Assembly 
```
erlc -S file.erl
```

Or alternatively, enter `erl` shell:
```erl
beam_disasm:file("file.beam").
```


