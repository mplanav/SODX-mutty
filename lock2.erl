-module(lock2).
-export([start/1]).

start(Id) ->
    spawn(fun() -> init(Id) end).

init(Id) ->
    receive
        {peers, Nodes} ->
            open(Nodes, Id);
        stop ->
            ok
    end.

open(Nodes, Id) ->
    receive
        {take, Master, Ref} ->
            Refs = requests(Nodes, Id),
            wait(Nodes, Master, Refs, [], Ref, Id);
        {request, From, Ref, FromId} when Id > FromId ->
            From ! {ok, Ref},
            open(Nodes, Id);
        {request, From, Ref, FromId} ->
            open(Nodes, Id, [{From, Ref, FromId}]);
        stop ->
            ok
    end.

open(Nodes, Id, Waiting) ->
    receive
        {take, Master, Ref} ->
            Refs = requests(Nodes, Id),
            wait(Nodes, Master, Refs, Waiting, Ref, Id);
        {request, From, Ref, FromId} ->
            open(Nodes, Id, [{From, Ref, FromId}|Waiting]);
        stop ->
            ok
    end.

requests(Nodes, Id) ->
    lists:map(
      fun(P) -> 
        R = make_ref(), 
        P ! {request, self(), R, Id}, 
        R 
      end, 
      Nodes).

wait(Nodes, Master, [], Waiting, TakeRef, Id) ->
    Master ! {taken, TakeRef},
    held(Nodes, Waiting, Id);
wait(Nodes, Master, Refs, Waiting, TakeRef, Id) ->
    receive
        {request, From, Ref, FromId} ->
            wait(Nodes, Master, Refs, [{From, Ref, FromId}|Waiting], TakeRef, Id);
        {ok, Ref} ->
            NewRefs = lists:delete(Ref, Refs),
            wait(Nodes, Master, NewRefs, Waiting, TakeRef, Id);
        release ->
            ok(Waiting),            
            open(Nodes, Id)
    end.

ok(Waiting) ->
    lists:map(
      fun({F,R, _}) -> 
        F ! {ok, R} 
      end, 
      Waiting).

held(Nodes, Waiting, Id) ->
    receive
        {request, From, Ref, FromId} ->
            held(Nodes, [{From, Ref, FromId}|Waiting], Id);
        release ->
            ok(Waiting),
            open(Nodes, Id)
    end.