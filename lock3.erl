-module(lock3).
-export([start/1]).

start(Id) ->
    spawn(fun() -> init(Id, 0) end).


init(Id, Clock) ->
    receive
        {peers, Nodes} ->
            open(Id, Nodes, Clock);
        stop -> ok
    end.


open(Id, Nodes, Clock) ->
    receive
        {take, Master, Ref} ->
            NewClock = Clock + 1,
            Refs = requests(Nodes, NewClock),
            wait(Id, Nodes, Master, Refs, [], Ref, NewClock);
        {request, From, Ref, Timestamp} ->
            NewClock = max(Clock, Timestamp) + 1,
            handle_request(Id, From, Ref, Timestamp, NewClock),
            open(Id, Nodes, NewClock);
        stop -> ok
    end.


requests(Nodes, Clock) ->
    lists:map(
        fun(P) ->
            R = make_ref(),
            P ! {request, self(), R, Clock},
            R
        end,
        Nodes
    ).


handle_request(Id, From, Ref, Timestamp, Clock) ->
    if
        Timestamp < Clock; (Timestamp == Clock andalso From < Id) ->
            From ! {ok, Ref};
        true ->
            ok
    end.


wait(Id, Nodes, Master, [], Waiting, TakeRef, Clock) ->
    Master ! {taken, TakeRef},
    held(Id, Nodes, Waiting, Clock);


wait(Id, Nodes, Master, Refs, Waiting, TakeRef, Clock) ->
    receive
        {request, From, Ref, Timestamp} ->
            NewClock = max(Clock, Timestamp) + 1,
            if
                Timestamp < Clock; (Timestamp == Clock andalso From < Id) ->
                    From ! {ok, Ref},
                    wait(Id, Nodes, Master, Refs, Waiting, TakeRef, NewClock);
                true ->
                    wait(Id, Nodes, Master, Refs, [{From, Ref} | Waiting], TakeRef, NewClock)
            end;
        {ok, Ref} ->
            NewRefs = lists:delete(Ref, Refs),
            wait(Id, Nodes, Master, NewRefs, Waiting, TakeRef, Clock + 1);
        release ->
            ok(Waiting),
            open(Id, Nodes, Clock + 1)
    end.


held(Id, Nodes, Waiting, Clock) ->
    receive
        {request, From, Ref, Timestamp} ->
            NewClock = max(Clock, Timestamp) + 1,
            held(Id, Nodes, [{From, Ref} | Waiting], NewClock);
        release ->
            ok(Waiting),
            open(Id, Nodes, Clock + 1)
    end.


ok(Waiting) ->
    lists:map(
        fun({F, R}) ->
            F ! {ok, R}
        end,
        Waiting
    ).