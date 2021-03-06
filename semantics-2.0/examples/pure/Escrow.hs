module Escrow where

import Semantics

escrow = Commit 1 1 1 
           (Constant 450) 10 100 
           (When 
              (OrObs 
                 (OrObs 
                    (AndObs 
                       (ChoseThis (1, 1) 0) 
                       (OrObs 
                          (ChoseThis (1, 2) 0) 
                          (ChoseThis (1, 3) 0))) 
                    (AndObs 
                       (ChoseThis (1, 2) 0) 
                       (ChoseThis (1, 3) 0))) 
                 (OrObs 
                    (AndObs 
                       (ChoseThis (1, 1) 1) 
                       (OrObs 
                          (ChoseThis (1, 2) 1) 
                          (ChoseThis (1, 3) 1))) 
                    (AndObs 
                       (ChoseThis (1, 2) 1) 
                       (ChoseThis (1, 3) 1)))) 90 
              (Choice 
                 (OrObs 
                    (AndObs 
                       (ChoseThis (1, 1) 1) 
                       (OrObs 
                          (ChoseThis (1, 2) 1) 
                          (ChoseThis (1, 3) 1))) 
                    (AndObs 
                       (ChoseThis (1, 2) 1) 
                       (ChoseThis (1, 3) 1))) 
                 (Pay 2 1 2 
                    (Committed 1) 100 Null Null) 
                 (Pay 3 1 1 
                    (Committed 1) 100 Null Null)) 
              (Pay 4 1 1 
                 (Committed 1) 100 Null Null)) Null
