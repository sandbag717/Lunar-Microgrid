r = readmatrix('Book 7 part 2(Azur Space) (2).csv');

valid = isfinite(r(:,1)) & isfinite(r(:,11)) & isfinite(r(:,12));

T = r(valid,1);
vm = r(valid,11);
im = r(valid,12);

[T,ix] = unique(T,'stable');
vm = vm(ix);
im = im(ix);

[P170_T,ix] = sort(T);
P170_Vmp = vm(ix);
P170_Imp = im(ix);

P170_dt = 1e-4;
P170_eta = 0.96;
P170_Gref = 1367;
P170_mppt_interval = 0.01;
