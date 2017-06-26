function aboxes = do_proposal_test_scut(conf, model_stage, imdb, roidb, cache_name, method_name)
    aboxes                      = proposal_test_scut(conf, imdb, ...
                                        'net_def_file',     model_stage.test_net_def_file, ...
                                        'net_file',         model_stage.output_model_file, ...
                                        'cache_name',       model_stage.cache_name); 
          
    fprintf('Doing nms ... ');                                
    aboxes                      = boxes_filter(aboxes, model_stage.nms.per_nms_topN, model_stage.nms.nms_overlap_thres, model_stage.nms.after_nms_topN, conf.use_gpu);      
    
    % eval the gt recall
    gt_num = 0;
    gt_re_num = 0;
    for i = 1:length(roidb.rois)
        gts = roidb.rois(i).boxes(roidb.rois(i).ignores~=1, :); % keep not ignores gt
        if ~isempty(gts)
            rois = aboxes{i}(:, 1:4); % proposal roidb
            max_ols = max(boxoverlap(rois, gts)); % compute IoU
            gt_num = gt_num + size(gts, 1); % count gt num
            gt_re_num = gt_re_num + sum(max_ols >= 0.5); % count recall gt num
        end
    end
    fprintf('gt recall rate = %.4f\n', gt_re_num / gt_num);

    fprintf('Preparing the results for scut evaluation ...');
    cache_dir = fullfile(pwd, 'output', conf.exp_name, 'rpn_cachedir', cache_name);
    res_boxes = aboxes;
    mkdir_if_missing(fullfile(cache_dir, method_name));
    % remove all the former results
    DIRS=dir(fullfile(fullfile(cache_dir, method_name))); 
    n=length(DIRS);
    for i=1:n
        if (DIRS(i).isdir && ~strcmp(DIRS(i).name,'.') && ~strcmp(DIRS(i).name,'..') ) % except . ..
            rmdir(fullfile(cache_dir, method_name ,DIRS(i).name),'s'); % remove include subdir
        end
    end
    
    assert(length(imdb.image_ids) == size(res_boxes, 1));
    for i = 1:size(res_boxes, 1)
        if ~isempty(res_boxes{i})
            sstr = strsplit(imdb.image_ids{i}, '_');
            mkdir_if_missing(fullfile(cache_dir, method_name, sstr{1}));
            fid = fopen(fullfile(cache_dir, method_name, sstr{1}, [sstr{2} '.txt']), 'a');
            % transform [x1 y1 x2 y2] to [x y w h], for matching the
            % scut evaluation protocol
            res_boxes{i}(:, 3) = res_boxes{i}(:, 3) - res_boxes{i}(:, 1); % h
            res_boxes{i}(:, 4) = res_boxes{i}(:, 4) - res_boxes{i}(:, 2); % w
            for j = 1:size(res_boxes{i}, 1)
                fprintf(fid, '%d,%f,%f,%f,%f,%f\n', str2double(sstr{3}(2:end))+1, res_boxes{i}(j, :)); % write aboxes roi
            end
            fclose(fid);
        end
    end
    fprintf('Done.');
    
    % copy results to eval folder and run eval script to get figure.
    folder1 = fullfile(pwd, 'output', conf.exp_name, 'rpn_cachedir', cache_name, method_name);
    folder2 = fullfile(pwd, 'external', 'code3.2.1', 'data-scut', 'res', method_name);
    mkdir_if_missing(folder2);
    copyfile(folder1, folder2);
    tmp_dir = pwd;
    cd(fullfile(pwd, 'external', 'code3.2.1'));
    dbEval_RPNBF;
    cd(tmp_dir);
end

function aboxes = boxes_filter(aboxes, per_nms_topN, nms_overlap_thres, after_nms_topN, use_gpu)
% do nms
    % to speed up nms
    if per_nms_topN > 0
        aboxes = cellfun(@(x) x(1:min(size(x, 1), per_nms_topN), :), aboxes, 'UniformOutput', false); % make sure box not excced, get 1:min(size(x, 1), per_nms_topN) aboxes
    end
    % do nms
    if nms_overlap_thres > 0 && nms_overlap_thres < 1
        if 0 %never run
            for i = 1:length(aboxes)
                tic_toc_print('weighted ave nms: %d / %d \n', i, length(aboxes));
                aboxes{i} = get_keep_boxes(aboxes{i}, 0, nms_overlap_thres, 0.7); %author del this func
            end 
        else
            if use_gpu
                for i = 1:length(aboxes)
                    tic_toc_print('nms: %d / %d \n', i, length(aboxes));
                    aboxes{i} = aboxes{i}(nms(aboxes{i}, nms_overlap_thres, use_gpu), :); % do nms
                end
            else
                parfor i = 1:length(aboxes)
                    aboxes{i} = aboxes{i}(nms(aboxes{i}, nms_overlap_thres), :);
                end
            end
        end
    end
    aver_boxes_num = mean(cellfun(@(x) size(x, 1), aboxes, 'UniformOutput', true));
    fprintf('aver_boxes_num = %d, select top %d\n', round(aver_boxes_num), after_nms_topN);
    if after_nms_topN > 0
        aboxes = cellfun(@(x) x(1:min(size(x, 1), after_nms_topN), :), aboxes, 'UniformOutput', false); % only keep after_nms_topN boxes
    end
end
