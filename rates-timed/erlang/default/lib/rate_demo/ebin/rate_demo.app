{application,rate_demo,
             [{description,"Parametric rate-based invariant demo"},
              {vsn,"0.1.0"},
              {registered,[rate_demo_sup,rate_consumer,queue_monitor]},
              {mod,{rate_demo_app,[]}},
              {applications,[kernel,stdlib]},
              {env,[]},
              {modules,[consumer,producer,queue_monitor,rate_demo_app,
                        rate_demo_sup]}]}.
