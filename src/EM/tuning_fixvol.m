function [gmm1, stats, covfunc] = tuning_fixvol(gmm2, K, varargin)
%TUNING_FIXVOL performs EMstyle GMM fitting with K components to
%GMM2.
%
%   EM_GMM_CLOSEST_FULL(GMM2, K)
%   EM_GMM_CLOSEST_FULL(GMM2, K, OPTION)
%
%   OPTION.maxiter = 100 default value.
%   OPTION.tol = 1e-6.
%   OPTION.debug = 1 returns detailed stats.
%   OPTION.debug = 2 show the intermediate fittings.
%   OPTION.getGamma = 'getGamma_xentropy', (default) responsibilities is 
%   evaluated by cross entproy.
%   OPTION.getGamma = 'getGamma_inprod', responsibilities is evaluated by
%   innerproduct.
%   OPTION.getGamma = 'getGamma_l2dist', responsibilities is evaluated by
%   l2 distance between mean functions and data Gaussian based on covfunc.
%   covfunc is the simplest covariance function (univariate Gaussian 
%   with l2 distance).
%
%   See Also : GD_GMMS_CLOSEST_FAST, SCRIPT_FOR_ALGORITHM_TUNING

%   $ Hyunwoo J. Kim $  $ 2015/04/19 13:09:02 (CDT) $ NO EPS -> MY EPS%
%   $ Hyunwoo J. Kim $  $ 2015/04/04 18:25:56 (CDT) $
    
    %% Random initialization
    % pick k Gaussians from GMM2
    global myeps
    myeps = 1e-100;

    %% Fixing volumn
    FIXVOL = 8.639999999999987e-15; %% Product of eigen values of desirable tensor.
    FIXVOLCOEFF = FIXVOL^(1/3);  %% Since it multiplied three times for product of eigen values.
    
    disp('Volume of tensors in input GMM is normalized');
    for i =1:gmm2.NComponents
        gmm2.Sigma(:,:,i) = volumenormalization(gmm2.Sigma(:,:,i), FIXVOL);
    end
    
    idx = randsample(1:gmm2.NComponents,K);
    %% Debugging
    c1 = 1; % initialization for  covariance fuction.
    c2 = 1e-4; % Random perturbation of Sigma initialization.
    
   
    % Full covariance matrix.
    assert(covtype(gmm2.Sigma) == 1, 'Covariance matrix MUST a full matrix.');
    if nargin <= 3
        noiseSigma = zeros(size(gmm2.mu,2),size(gmm2.mu,2),K);
        for i =1:K
            v = abs(randn(3,1));
            v = v/norm(v);
            noiseSigma(:,:,i) = 10*c2*v*v'+c2*eye(size(gmm2.mu,2)); %% Random direction.
            %% New code. 
            ww = rand(size(gmm2.Sigma,3),1);
            S = zeros(size(gmm2.mu,2));
            for iS = 1:size(gmm2.Sigma,3)
              S = S + gmm2.Sigma(:,:,iS)*ww(iS);
            end
            noiseSigma(:,:,i) = S/sum(ww);
            
            %noiseSigma(:,:,i) = rand(size(gmm2.Sigma,3),1); %% Random direction.
            
            %df = size(gmm2.mu,2)+1;
            %noiseSigma(:,:,i) = c2*wishrnd(eye(size(gmm2.mu,2)),df)/df;
            %noiseSigma(:,:,i) = c2*eye(size(gmm2.mu,2));
        end
        %gmm1 = gmdistribution(gmm2.mu(idx,:), gmm2.Sigma(:,:,idx)+noiseSigma, ones(1,K)/K);
        gmm1 = gmdistribution(gmm2.mu(idx,:), noiseSigma, rand(1,K)/K);
        gmm1 = obj2structGMM(gmm1);
    else
        gmm1 = varargin{2};
        if ~isstruct(gmm1);
            gmm1 = obj2structGMM(gmm1);
        end
    end
    gmm1init = gmm1;
    
    N = gmm2.NComponents;
    dims = size(gmm2.mu,2);
    
    if nargin >= 3
        option = varargin{1};
    else 
        option = [];
    end
    if isfield(option,'maxiter')
        maxiter = option.maxiter;
    else 
        maxiter = 300; 
    end

    if isfield(option, 'debug') && (option.debug >= 1)
        debug = option.debug;
    else 
        debug = 0;
    end
    
    if isfield(option, 'tol')
        tol = option.tol;
    else
        tol = 1e-6;
    end
    
	if isfield(option, 'dflag')
        dflag = option.dflag;
	else
        dflag = ones(1,3);
    end
    
    covfunc = [];
    if isfield(option,'getGamma')
        if strcmpi(option.getGamma,'getGamma_inprod')
            getGamma = @getGamma_inprod;
        elseif strcmpi(option.getGamma,'getGamma_l2dist')
            getGamma = @getGamma_l2distance; 
            covfunc = ones(K,1)*c1+c1*(1/10)*rand(K,1);
        elseif strcmpi(option.getGamma,'getGamma_l2dist2')
            getGamma = @getGamma_l2distance2; 
            covfunc = ones(K,1)*c1+c1*(1/10)*rand(K,1);
        elseif strcmpi(option.getGamma,'getGamma_xentropy')
            getGamma = @getGamma_xentropy; 
        else
            error('Undefined Gamma option.')
        end
    else
        getGamma = @getGamma_xentropy; 
    end
    
    if isfield(option, 'monotonicity')
        monotonicity = option.monotonicity;
    else
        monotonicity = false;
    end
    
    l2history = zeros(maxiter,1);
    stats =[];
    stats.terminate = 'Not converged.';
    diffnorm = 10000; % Inf
    
    %% debug = 1;
    
%     if length(idx) > 1
%         gmm2.Sigma(:,:,idx)
%         debug = 1;
%     end
    for iter = 1:maxiter
        %iter
        if debug >= 1
            l2history(iter) = l2distGMM(gmm1,gmm2);
            fprintf('Eval : %f, diffnorm %e tol %e \n', l2history(iter), diffnorm, tol);
        end

        %%% E-step %%%
        %% Calculate responsibilies.
        gammas =  getGamma(gmm1, gmm2, covfunc);
        gmm1new = gmm1;
        
%         gmm1.Sigma;
%
%         covfunc;
        %%% M-step %%%
        %
        %% Calculate Mean and Variance of each components.
        % Mean update (Weighted mean of means of all Gaussians)
        % mubar = sum mu*gamma / sum gamma
        
        W2 = gmm2.PComponents(:); % Weight of gmm2. Data Gaussian mixture models.
        if dflag(2) == 1
            % mu update 
            for j = 1:K
                W2J = W2.*gammas(:,j);
                gmm1new.mu(j,:) = sum(repmat(W2J,1,dims).*gmm2.mu,1)/sum(W2J);
            end
        end
    
        % Sigma udpate
        if dflag(3) == 1
            for j = 1:K
                % sum alpha_i C_i + sum alpha_i (mu_i-mubar)(mu_i-mubar)'
                Sigma = zeros(dims);
                W2J = W2.*gammas(:,j);
                for i = 1:N
                    Sigma = Sigma + gmm2.Sigma(:,:,i)*W2J(i);
                end
                mSigma = Sigma/sum(W2J);
                M = gmm2.mu - repmat(gmm1new.mu(j,:), N, 1);
                mSigma = volumenormalization(mSigma, FIXVOL);
                %mSigma = mSigma/(prod(eig(mSigma))^(1/3))*FIXVOLCOEFF;
                try
                    assert(isspd(mSigma))
                    gmm1new.Sigma(:,:,j) = mSigma + M'*diag(W2J)*M/sum(W2J);
                catch
                    disp('Numerical problem.')
                end
                
            end
        end
        
        % pi update (PComponents)
        if dflag(1) == 1
            pi2gammas = repmat(W2,1,K).*gammas;
            w = sum(pi2gammas, 1);
            gmm1new.PComponents = w/sum(w);
        end
        
        diffcovfunc = 0;
        % Cov function update (covfunc)
        if ~isempty(covfunc)
            covfunc_old = covfunc;
            covfunc = getCovfunc(gmm1, gmm2, gammas);
            diffcovfunc = covfunc-covfunc_old;
        end
        
        % Stopping condition
        diffmu = gmm1new.mu - gmm1.mu;
        diffS = gmm1new.Sigma - gmm1.Sigma;
        diffpi = gmm1new.PComponents - gmm1.PComponents;
        
        gmm1 = gmm1new;
        %diffnorm = norm(diffmu)+norm(diffS(:))+norm(diffpi);
        %+norm(diffcovfunc);
        diffnorm = norm(diffmu)+norm(diffS(:))+norm(diffpi)+norm(diffcovfunc);
        if diffnorm < tol 
            stats.terminate = 'Converged.';
            break;
        end
        
        if monotonicity && iter >1 && (l2history(iter-1) < l2history(iter))
            stats.terminate = 'Coverged.';
            break;
        end
        
        if mod(iter,10) == 1 && debug >= 2
            gmmhat = struct2objGMM(gmm1);
            figure
            hold on
            ezcontourf(@(x,y)log(pdf(gmmhat,[x y])),[-0.3 1],[-0.3 1]);
            plot(gmm2.mu(:,1), gmm2.mu(:,2), 'b.');
            title(sprintf('K means style GMM fitting iter: %d.',iter))
            hold off
        end        
    end
    
    stats.iter = iter;
    stats.gmm1init = gmm1init;
    if debug
        stats.l2history = l2history(1:iter);
    end
end

function gammas = getGamma_l2distance2(gmm1, gmm2, covfunc)
    global myeps
    K = gmm1.NComponents;
    N = gmm2.NComponents;
    % L2D NxK
    L2D = getl2distofcomponents(gmm2, gmm1); % GMM2 is data with N comps.
    % GAMMAS NxK
    % r(z_ij) := wj exp( -||f_i - g_j ||^2/(2*covfuc_j) )
    %           /sum wk exp( -||f_i - g_k ||^2/(2*covfuc_k) )
    
    % exp( -||f_i - g_j ||^2/(2*covfuc_j)
    %L2D = L2D - min(min(L2D)); %% Numerical stability
    gammas = -log(repmat(sqrt(covfunc(:)'),N,1))-.5*L2D./repmat(covfunc(:)',N,1); 
    % wj exp( -||f_i - g_j ||^2/(2*covfuc_j) )
    gammas = log(repmat(gmm1.PComponents,N,1))+gammas;
    % r(z_ij)
%     %gammas = max(gammas ,eps); % To prevent the division by zero.
%     tmp = gammas - repmat(min(gammas,[],2),1,K);
%     
%     if sum(tmp(:) > 100,1)
%         tmp = tmp./norm(tmp);
%     end
%   gammas = exp(tmp); % SafeGaurad
    gammas = exp(gammas)+myeps; % SafeGaurad
    gammas = gammas./repmat(sum(gammas,2),1,K)+myeps;
    try
        assert(isreal(gammas) && ~sum(isnan(gammas(:))))
    catch
        disp('Numerial problem');
    end
    
end

function gammas = getGamma_l2distance(gmm1, gmm2, covfunc)
    K = gmm1.NComponents;
    N = gmm2.NComponents;
    % L2D NxK
    L2D = getl2distofcomponents(gmm2, gmm1); % GMM2 is data with N comps.
    % GAMMAS NxK
    % r(z_ij) := wj exp( -||f_i - g_j ||^2/(2*covfuc_j) )
    %           /sum wk exp( -||f_i - g_k ||^2/(2*covfuc_k) )
    
    % exp( -||f_i - g_j ||^2/(2*covfuc_j)
    L2D = L2D - min(min(L2D)); %% Numerical stability
    gammas = exp(-L2D./repmat(covfunc(:)',N,1)); 
    % wj exp( -||f_i - g_j ||^2/(2*covfuc_j) )
    gammas = repmat(gmm1.PComponents,N,1).*gammas;
    % r(z_ij)
    gammas = max(gammas ,eps); % To prevent the division by zero.
    gammas = gammas./repmat(sum(gammas,2),1,K);
    try
        assert(isreal(gammas) && ~sum(isnan(gammas(:))))
    catch
        disp('Numerial problem');
    end
    
end

function covfunc = getCovfunc(gmm1, gmm2, gammas, varargin)
    global myeps
    % GMM1 is a variance g :={g_j} with K comps w_j
    % GMM2 is a data f:= {f_i} with N comps pi_i
    K = gmm1.NComponents;
    
    % L2D K x N  , NOTE THIS DIFFERS FROM it in GETGAMMA_L2DISTANCE.
    L2D = getl2distofcomponents(gmm1, gmm2); % GMM2 is data with N comps.
    % covfunc_j = sum_i r_ji*pi_i [ ||f_i ||^2 - 2 sum_i pi_i <f_i, g_j>
    %             + ||g_j ||^2 ]
    % GAMMA is N x K. r_ij. WJI := GAMMA_JI.*PI_I
    WJI = gammas'.*repmat(gmm2.PComponents,K,1);
    covfunc = sum(WJI.*L2D,2)./sum(WJI,2); % Right normalization.
    %covfunc = sum(WJI.*L2D,2);
    covfunc = max(covfunc, myeps);
    % Ad-hoc
    % covfunc = min(covfunc, 0.5); %% It was 2. No need adhoc algorithm.
end

function gammas = getGamma_inprod(gmm1, gmm2, varargin)
    K = gmm1.NComponents;
    N = gmm2.NComponents;
    gammas = zeros(N,K);
    for i = 1:N
        for j = 1:K 
            gammas(i,j) = innerprodGaussian(gmm2.mu(i,:), gmm1.mu(j,:), gmm2.Sigma(:,:,i), gmm1.Sigma(:,:,j));
        end
    end
    gammas = repmat(gmm1.PComponents,N,1).*gammas;
    gammas = gammas./repmat(sum(gammas,2),1,K);
end

%% GMM1 is variable. K-GMM.
%% GMM2 is data. N-GMM.
function gammas = getGamma_xentropy(gmm1, gmm2, varargin)
    K = gmm1.NComponents;
    N = gmm2.NComponents;
    gammas = zeros(N,K);

    for i = 1:N
        for j = 1:K 
            gammas(i,j) = -crossentropy(gmm2.mu(i,:)', gmm2.Sigma(:,:,i), gmm1.mu(j,:)', gmm1.Sigma(:,:,j));
        end
    end
    gammas = gammas - min(min(gammas));
    gammas = exp(gammas);
    gammas = repmat(gmm1.PComponents,N,1).*gammas;
    gammas = gammas./repmat(sum(gammas,2),1,K);
end

function L2D = getl2distofcomponents(gmm1, gmm2)
    K = gmm1.NComponents;
    N = gmm2.NComponents;
    L2D = zeros(K,N);
    
    for i=1:K
        for j = 1:N
            L2D(i,j) = l2distGaussian(gmm1.mu(i,:), gmm1.Sigma(:,:,i),...
                                      gmm2.mu(j,:), gmm2.Sigma(:,:,j));
        end
    end
    try
        assert(isreal(L2D) && ~sum(isnan(L2D(:))))
    catch
        disp('Numerial problem');
    end
    
end

function l2 = getl2normofcomponents(gmm)
    l2 = zeros(gmm.NComponents,1);
    for i = 1:K
        l2(i) = innerprodGaussian(gmm.mu(i,:), gmm.mu(i,:), ...
            gmm.Sigma(:,:,i),gmm.Sigma(:,:,i));
    end
end








