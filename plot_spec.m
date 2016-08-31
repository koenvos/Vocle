function plot_spec(xb, xa, fs, color)
persistent min_fx max_fx;

if nargin < 2, xa = 1; end
if nargin < 3, fs = 1; end
if size(xa, 1) == 1, xa = xa'; end
if size(xb, 1) == 1, xb = xb'; end

nfft = max(2^13, 2^ceil(log2(max(length(xa), length(xb))+1)));
f = (0:nfft/2)'/nfft * fs;
if size(xb, 1) > 1
    fxb = fft(xb, nfft); fxb = fxb(1:nfft/2+1, :);
else
    fxb = xb;
end
if size(xa, 1) > 1
    fxa = fft(xa, nfft); fx = bsxfun(@times, 1 ./ fxa(1:nfft/2+1, :), fxb);
else
    fx = fxb;
end
if nargin > 3
    hold on;
    plot(f, 20*log10(abs(fx)), color);
    hold off;
else
    plot(f, 20*log10(abs(fx)));
    min_fx =  inf;
    max_fx = -inf;
end
ax = axis;
lvls = sort(20*log10(abs(fx(:))+eps));
max_fx = max(max_fx, lvls(end));
min_fx = min(min_fx, lvls(round(end*0.02)));
axis([0, fs/2, max(ax(3), min_fx-3), min(ax(4), max_fx+3)]);
grid on;
