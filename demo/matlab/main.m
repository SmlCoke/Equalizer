% main.m
clc
clear
%bpsk without multi_path from bertool
load('bpsk_theory.mat');
%******************** Preparation part *************************************
sr = 256000;     % Symbol rate
ml = 1;          % ml:Number of modulation levels (BPSK:ml=1)
br = sr .* ml;   % Bit rate
nd = 10000;       % Number of symbols that simulates in each loop
ebn0 = 0:30;      % Eb/N0
ber = zeros(1,length(ebn0)); %ber without eq
eq_ber = zeros(1,length(ebn0)); %ber with eq
% eq_ber2 = zeros(1,length(ebn0)); %ber with eq2
multi_path = 1;		% 1 = multi_path; 0 = no multi_path

%******************** START CALCULATION *************************************

nloop = 100;  % Number of simulation loops

tic;
% efn = 20;  % tap number of equalization filter
for cnt = 1:length(ebn0)
    disp(ebn0(cnt));    % currnt ebn0
    noe = 0;    % Number of error data
    eq_noe = 0;
%     eq_noe2 = 0;
    nod = 0;    % Number of transmitted data
    for i=1:nloop
        
        %*************************** Data generation ********************************
        
        data0 = rand(1, nd*ml) > 0.5;  % rand: built in function
        
        %*************************** BPSK Modulation ********************************
        
        data1 = data0.*2-1;
        
        %************************************** Channel************************

        switch multi_path
            case 0
                data2 = data1;
            case 1
                mpc = [1, 0.9, 0.8]; %multi path coefficient
				data2 = filter(mpc, 1, data1); %filter: built in function
        end

        %**************************** Attenuation Calculation ***********************
        
        spow=sum(data2.*data2)/nd;  % sum: built in function
        attn=0.5*spow*sr/br*10.^(-ebn0(cnt)/10);
        attn=sqrt(attn);  % sqrt: built in function
        
        %********************* Add White Gaussian Noise (AWGN) **********************
        
        awgn = randn(1,length(data2)).*attn;
        data3 = data2 + awgn;

        %*************************** Equalization filter ********************************

        h = [1, -0.9, 0.01];
        % todo: fix-point       e.g. fix_data = fi(data, 1, 8, 5);
        data4 = filter(h, 1, data3);
%         hh = ? ; %�����ͷ���˲��� 1 * efn
%         data5 = filter(hh, 1, data3);
       
        %**************************** BPSK Demodulation *****************************
        
        demodata = zeros(1,ml*nd);
        demodata(1:ml*nd)=data3(1:ml*nd)>=0;
        eq_demodata = zeros(1,ml*nd);
        eq_demodata(1:ml*nd)=data4(1:ml*nd)>=0;
%         eq_demodata2 = zeros(1,ml*nd);
%         eq_demodata2(1:ml*nd)=data5(1:ml*nd)>=0;
        
        %************************** Bit Error Rate (BER) ****************************
        
        eq_noe_i=sum(abs(data0-eq_demodata));  % sum: built in function
        noe_i=sum(abs(data0-demodata));  % sum: built in function
        nod_i=length(data0);  % length: built in function
%         eq_noe2_i=sum(abs(data0-eq_demodata2));  % sum: built in function
%         eq_noe2=eq_noe2+eq_noe2_i;
        eq_noe=eq_noe+eq_noe_i;
        noe=noe+noe_i;
        nod=nod+nod_i;

    end % for i=1:nloop
    ber(cnt) = noe/nod;
    eq_ber(cnt) = eq_noe/nod;
%     eq_ber2(cnt) = eq_noe2/nod;
end
toc;

%********************** Output result ***************************

disp(['frame=',num2str(nloop)]);
disp(['BER=',num2str(ber)]);
disp(['EQ_BER=  ',num2str(eq_ber)]);
% disp(['EQ_BER2=  ',num2str(eq_ber2)]);
toc;

%******************** end of file ***************************
% BER���߻��ƣ������ο�
figure(1);
axis([0 30.5 1.0e-7 1]);
semilogy (ebn0_theory_bpsk, ber_theory_bpsk,'-k>','linewidth',3,'MarkerSize',8);
hold on ;
axis([0 30.5 1.0e-7 1]);
semilogy (ebn0, ber, '-b<', 'linewidth',3, 'MarkerSize',8);
axis([0 30.5 1.0e-7 1]);
semilogy (ebn0, eq_ber, '-g<', 'linewidth',3, 'MarkerSize',8);
legend ('no-multi', 'multi w/o equ', 'multi w/ equ');
% semilogy (ebn0, eq_ber2, '-m<', 'linewidth',3, 'MarkerSize',8);
% legend ('no-multi', 'multi w/o equ', 'multi w/ equ', 'multi w/ equ2');
title('Multipath Simulation');
grid on ;
hold off;

% �����źŷֲ����ƣ������ο�
figure(2);
axis([-5 5 0 1]);
std_c = [ones(nd*ml, 1) .* data0', zeros(nd*ml, 1), ones(nd*ml, 1) .* (1 - data0)'];
scatter(data3(1:ml*nd), ones(1, ml*nd) .* 0.2, [], std_c);
hold on ;
axis([-5 5 0 1]);
scatter(data4(1:ml*nd), ones(1, ml*nd) .* 0.8, [], std_c);
% scatter(data5(1:ml*nd), zeros(1, ml*nd), 'red');
title('Signal Distribution');
grid on ;
hold off;

