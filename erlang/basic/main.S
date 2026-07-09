{module, main}.  %% version = 0

{exports, [{module_info,0},{module_info,1},{start,0}]}.

{attributes, []}.

{labels, 17}.


{function, start, 0, 2}.
  {label,1}.
    {line,[{location,"main.erl",4}]}.
    {func_info,{atom,main},{atom,start},0}.
  {label,2}.
    {allocate_heap,1,{alloc,[{words,1},{floats,0},{funs,1}]},0}.
    {init_yregs,{list,[{y,0}]}}.
    {bif,self,{f,0},[],{x,0}}.
    {make_fun3,{f,16},0,0,{x,0},{list,[{x,0}]}}.
    {line,[{location,"main.erl",6}]}.
    {call_ext,1,{extfunc,erlang,spawn,1}}.
    {move,{x,0},{y,0}}.
    {move,{literal,{go,1}},{x,1}}.
    {line,[{location,"main.erl",8}]}.
    send.
  {label,3}.
    {loop_rec,{f,5},{x,0}}.
    {test,is_tuple,{f,4},[{x,0}]}.
    {test,test_arity,{f,4},[{x,0},3]}.
    {get_tuple_element,{x,0},0,{x,1}}.
    {get_tuple_element,{x,0},1,{x,0}}.
    {test,is_eq_exact,{f,4},[{x,0},{atom,og}]}.
    {test,is_eq_exact,{f,4},[{x,1},{tr,{y,0},pid}]}.
    remove_message.
    {move,{atom,ok},{x,1}}.
    {move,{y,0},{x,0}}.
    {line,[{location,"main.erl",10}]}.
    {call_ext_last,2,{extfunc,erlang,exit,2},1}.
  {label,4}.
    {loop_rec_end,{f,3}}.
  {label,5}.
    {wait,{f,3}}.


{function, consumer, 1, 7}.
  {label,6}.
    {line,[{location,"main.erl",13}]}.
    {func_info,{atom,main},{atom,consumer},1}.
  {label,7}.
    {allocate,2,1}.
    {move,{x,0},{y,1}}.
    {bif,self,{f,0},[],{y,0}}.
  {label,8}.
    {loop_rec,{f,10},{x,0}}.
    {test,is_tagged_tuple,{f,9},[{x,0},2,{atom,go}]}.
    {get_tuple_element,{x,0},1,{x,0}}.
    remove_message.
    {line,[{location,"main.erl",17}]}.
    {gc_bif,'+',{f,0},1,[{x,0},{integer,1}],{x,2}}.
    {move,{atom,og},{x,1}}.
    {move,{y,1},{x,3}}.
    {move,{y,0},{x,0}}.
    {trim,2,0}.
    {call_fun,3}.
    {call_ext_last,1,{extfunc,erlang,send,1},0}.
  {label,9}.
    {loop_rec_end,{f,8}}.
  {label,10}.
    {wait,{f,8}}.


{function, module_info, 0, 12}.
  {label,11}.
    {line,[]}.
    {func_info,{atom,main},{atom,module_info},0}.
  {label,12}.
    {move,{atom,main},{x,0}}.
    {call_ext_only,1,{extfunc,erlang,get_module_info,1}}.


{function, module_info, 1, 14}.
  {label,13}.
    {line,[]}.
    {func_info,{atom,main},{atom,module_info},1}.
  {label,14}.
    {move,{x,0},{x,1}}.
    {move,{atom,main},{x,0}}.
    {call_ext_only,2,{extfunc,erlang,get_module_info,2}}.


{function, '-start/0-fun-0-', 1, 16}.
  {label,15}.
    {line,[{location,"main.erl",6}]}.
    {func_info,{atom,main},{atom,'-start/0-fun-0-'},1}.
  {label,16}.
    {call_only,1,{f,7}}. % consumer/1
