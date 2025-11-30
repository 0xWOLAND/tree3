# Some more notes on combinators

> Two programs can extensionally be equivalent (same input-output relations) but intensionally be different. 

A _combinator_ $M$ is a function of the form 

$$
    M x_1 x_2 \cdots x_n = t
$$

where $x_i$ are variables and $t$ is some combination built by application. So $M$ is a function which takes some combinators $N_1, \cdots, N_n$ and produces the a sequence 

$$
    M N_1 N_2 \cdots N_n = \{N_1 / x_1\} \{N_2/x_2\} \cdots \{N_n/x_n\} t
$$

Where we are substituting $N$ for $x$ in $t$ by $\{N/x\}t$. 

The set of combinators for Tree Calculus is 
$$
    Ix = x \\
    Kxy = x \\
    Sxyz = xz(yz) \\
    Bfxy = fyx \\
    Cgfx = g(fx) \\
    Dxyz = yz(xz) \\
$$

> Combinators can be applied to each other (no need for variables) and can be reduced directly

All combinators can be represented in tree calculus, so it is _combinatorially complete_. 


## Fixpoints
Recursion can be represented in fixpoint functions using a $Y$ combinator such that for any $f$ 

$$
    Y f = f(Y f)
$$

For example, if $f = K I$ then 
$$
    Y (KI) x = KI(Yf)x = x
$$
where $Y(KI)$ is an **identity function**.

Ex. if $f = I$ then 

$$
Y I x = I(YI)x = YIx
$$

But not all seraches need to be terminating. To make recursive functions that don't have to eagerly evaluate $Y f$, we can instead evaluate $Yfx$ on any function argument $x$. Hence, we get the _wait_ arguemnt 

$$
    \text{wait} \{x,y\} = d\{I\} (d\{Ky\}(Kx))
$$
