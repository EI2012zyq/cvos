
% @param: boxes: struct with following fields
%   * y, x : location of center in image
%   * r : determines box size
%
% @note: b.fg_prob{,_colour,_shape} all in frame t-1
% TODO(vasiliy): can divisions result in NaNs here?
function [boxes_out, valid] = warp_bboxes_forward(boxes, layers, uvf, ...
  WARPSAFESPEED)

if ~exist('WARPSAFESPEED'); WARPSAFESPEED = 20; end;

boxes_out = boxes;
valid = [];

if isempty(boxes);
  return;
end

[rows, cols, ~] = size(uvf);
uvf(isnan(uvf) | isinf(uvf)) = 0.0;
n = size(boxes, 1);
valid = true(n, 1);

mag_uvf = sqrt(sum(uvf .^ 2, 3));

for k = 1:n;
  b = boxes(k);
  y = round(b.y);
  x = round(b.x);
  r = b.r;

  ymin = max(1,    y - r);
  ymax = min(rows, y + r);
  xmin = max(1,    x - r);
  xmax = min(cols, x + r);
  
  ysz = ymax - ymin + 1;
  xsz = xmax - xmin + 1;

  ys = ymin:ymax;
  xs = xmin:xmax;

  % TODO: hope fg_mask isn't empty, but might need to check later
  % if sum(b.fg_mask(:)) <= 0.02 * ysz * xsz;
  %   msk = ones(ysz, xsz);
  % end
  
  % msk = b.fg_mask > 0.5;
  % u = uvf(ys,xs,1);
  % v = uvf(ys,xs,2);
  % ub = mean(vec(u(msk)));
  % vb = mean(vec(v(msk)));

  msk = (b.fg_mask > 0.5) .* b.fg_prob .* b.gmm_learn_colour_mask;
  den = sum(msk(:));
  if (den >= 1.0);
    u = uvf(ys,xs,1) .* msk;
    v = uvf(ys,xs,2) .* msk;
    ub = sum(u(:)) / den;
    vb = sum(v(:)) / den;
  else
    % remove it, since fg_prob doesn't align with segmentation
    valid(k) = false;
    continue;
  end
  
  y_new = y + vb;
  x_new = x + ub;

  % remove boxes that go off the edge of the image
  if (y_new >= 1) && (y_new <= rows) && (x_new >= 1) && (x_new <= cols);
    boxes_out(k).y = y_new;
    boxes_out(k).x = x_new;
  else
    valid(k) = false;
  end
  
  % incorporate warp weight
  mag_uv_box = mag_uvf(ys, xs);
  mag_uv_box_avg = mean(mag_uv_box(:));
  mag_uv_box_fg = sqrt(ub * ub + vb * vb);
  conf_warp = exp(- mag_uv_box_fg / max(WARPSAFESPEED, mag_uv_box_avg));
  boxes_out(k).conf = boxes(k).conf * conf_warp;
end

boxes_out = boxes_out(valid);
end
