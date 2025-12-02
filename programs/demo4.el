; Unhalting recursive program: builds a self-referential loop.
; THIS WILL NOT HALT :P
(define-rec loop (pair loop loop))
(loop loop)
