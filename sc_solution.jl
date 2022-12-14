using DifferentialEquations,ComponentArrays,SparseDiffTools,LinearAlgebra
using Parameters: @unpack

function u0(X)
    #Given the initial center X, builds the initial conditions for the initial value problem.
    temp = X*transpose(X)
    ComponentArray( y=zero(X),x=X,Δ=zero(eltype(X)),jac_y= zero(temp),jac_x=one(temp))
end

function ModifiedHamiltonianProblem(fy,fx,initial_condition,tspan,par=nothing)
    function F!(du,u,par,t)
        @unpack x,y,Δ,jac_y,jac_x = u
    
        #Differential equation for y and x
        du.y = fy(y,x,par)
        du.x = fx(y,x,par)

        #Differential equation for the area Δ
        du.Δ = y⋅du.x
    
        #Differential equation for the jacobians
        for n in axes(jac_y,2)
            du.jac_y[:,n] = @views auto_jacvec(y->fy(y,x,par), y, jac_y[:,n]) + auto_jacvec(x->fy(y,x,par), x, jac_x[:,n])
            du.jac_x[:,n] = @views auto_jacvec(y->fx(y,x,par), y, jac_y[:,n]) + auto_jacvec(x->fx(y,x,par), x, jac_x[:,n])
        end
        
    end
    
    ODEProblem( F!, initial_condition, tspan, par)
end

weak_condition(u,t,integrator) = det(u.jac_x)
weak_affect!(integrator) = terminate!(integrator)
weak_callback = ContinuousCallback(weak_condition,strong_affect!,save_positions=(false,false))

strong_condition(u,t,integrator) = -10 < u.Δ < 1 && det(u.jac_x) != 0
function strong_affect!(integrator)
    integrator.u = zero(integrator.u)
end
strong_callback = ContinuousCallback(strong_condition,strong_affect!,save_positions=(false,false))


function solve_equations(θ,par,fy,fx,getNodesAndWeights,H;
    output_func=(sol,i,θ,par,node,weight)->(sol,false),reduction=(sols,θ)->sols,alg=BS3(),reltol=1e-1,abstol=1e-2,callback=strong_callback)
    #=Returns the solution of the ModifiedHamiltonianProblem 
    for each initial condition in nodes, in the interval (0,θ_max)=#

    θ = float.(θ)
    
    nodes,weights = applicable(getNodesAndWeights,par) ? getNodesAndWeights(par) : getNodesAndWeights(θ,par)
    prob = ModifiedHamiltonianProblem(fy,fx,u0(nodes[1]),(0,last(θ)/2),par)

    #Changes the initial condition after each run
    function prob_func(prob,i,repeat)
        remake(prob,u0=ComponentArray(prob.u0,x=nodes[i]))
    end

    ensemble_prob = EnsembleProblem(prob,prob_func=prob_func,output_func=(sol,i)->output_func(sol,i,θ,par,nodes,weights,H))

    if typeof(θ) <: AbstractArray
        sols = solve(ensemble_prob,alg,trajectories=length(nodes),reltol=reltol,abstol=abstol,
        callback=callback,saveat=θ/2)
    else
        sols = solve(ensemble_prob,alg,trajectories=length(nodes),reltol=reltol,abstol=abstol,
        callback=callback,save_start=false,save_everystep=false)
    end   

    reduction(sols,θ)
end

#=function solve_equations(θs::AbstractArray,par,fy,fx,getNodesAndWeights;
    output_func=(sol,i,θ,par,node,weight)->(sol,false),reduction=(sols,θ)->sols,alg=BS3(),reltol=1e-1,abstol=1e-2,stop_at_caustic=true)
    #=Returns the solution of the ModifiedHamiltonianProblem 
    for each initial condition in nodes, in the interval (0,θ_max)=#
    
    nodes,weights = getNodesAndWeights(par)
    prob = ModifiedHamiltonianProblem(fy,fx,u0(nodes[1]),(0,last(θs)/2),par)

    #Changes the initial condition after each run
    function prob_func(prob,i,repeat)
        remake(prob,u0=ComponentArray(prob.u0,x=nodes[i]))
    end

    ensemble_prob = EnsembleProblem(prob,prob_func=prob_func,output_func=(sol,i)->output_func(sol,i,θs,par,nodes[i],weights[i]))

    if stop_at_caustic
        condition(u,t,integrator) = u.Δ < 1 && det(u.jac_x) != 0 && u.Δ > -10    #This will return true if det(u.jac_x)==0
        #affect!(integrator) = terminate!(integrator)       #We terminate the solution when the condition is true
        function affect!(integrator)
            integrator.u = zero(integrator.u)
        end
        cb = ContinuousCallback(condition,affect!,save_positions=(false,false))
    else
        cb = nothing
    end

    sols = solve(ensemble_prob,alg,trajectories=length(nodes),reltol=reltol,abstol=abstol,callback=cb,saveat=θs/2)

    reduction(sols,θs)
end=#