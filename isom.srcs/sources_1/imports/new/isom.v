`timescale 1ns / 1ps


module isom
    #(
        parameter DIM = 1000,
        parameter LOG2_DIM = 10,    // log2(DIM)
        parameter DIGIT_DIM = 2,    // should be log2 of k
        parameter signed k_value = 1,
        
        parameter ROWS = 10,
        parameter LOG2_ROWS = 4,   // log2(ROWS)
        parameter COLS = 10,
        parameter LOG2_COLS = 4,     
        
        parameter TRAIN_ROWS = 75,
        parameter LOG2_TRAIN_ROWS = 7, // log2(TRAIN_ROWS)
        parameter TEST_ROWS = 150,
        parameter LOG2_TEST_ROWS = 8,  // log2(TEST_ROWS)
        
        parameter NUM_CLASSES = 3+1,
        parameter LOG2_NUM_CLASSES = 1+1, // log2(NUM_CLASSES)  
        
        parameter TOTAL_ITERATIONS=8,              
        parameter LOG2_TOT_ITERATIONS = 6,
        
        parameter INITIAL_NB_RADIUS = 3,
        parameter NB_RADIUS_STEP = 1,
        parameter LOG2_NB_RADIUS = 3,
        parameter ITERATION_NB_STEP = 5, // total_iterations / nb_radius_step
        
        parameter INITIAL_UPDATE_PROB = 1000,
        parameter UPDATE_PROB_STEP = 50,
        parameter LOG2_UPDATE_PROB = 10,
        parameter ITERATION_STEP = 1,          
        parameter STEP = 19,
        
        parameter RAND_NUM_BIT_LEN = 10
    )
    (
        input wire clk,
        output wire [LOG2_TEST_ROWS:0] prediction,
        output wire completed
    );

    ///////////////////////////////////////////////////////*******************Declare enables***********/////////////////////////////////////
    reg [1:0] variable_init_en=1;
    reg [1:0] training_en = 1;
    reg [1:0] next_iteration_en=0;
    reg [1:0] next_x_en=0;    
    reg [1:0] dist_enable = 0;
    reg [1:0] init_neigh_search_en=0;  
    reg [1:0] nb_search_en=0;
    reg train_multi_bmu_en=0;
    reg [1:0] test_en = 0;
    reg [1:0] classify_x_en = 0;
    reg [1:0] classify_weights_en = 0;
    reg [1:0] init_classification_en=0;
    reg [1:0] classification_en = 0;
    reg [1:0] class_label_en=0;
    reg multi_bmu_en=0;
    reg next_prediction_en=0;
    reg write_en = 0;
    reg is_completed = 0;
    
    ///////////////////////////////////////////////////////*******************Other variables***********/////////////////////////////////////
    
    reg signed [LOG2_TOT_ITERATIONS:0] iteration;
    
    reg [LOG2_ROWS:0] ii = 0;
    reg [LOG2_COLS:0] jj = 0;
    reg [LOG2_NUM_CLASSES:0] kk = 0;
    
    reg [LOG2_COLS:0] bmu [1:0];
    reg [LOG2_TRAIN_ROWS:0] class_frequency_list [ROWS-1:0][COLS-1:0][NUM_CLASSES-1:0];
    
    ///////////////////////////////////////////////////////*******************File read variables***********/////////////////////////////////////
    
    reg [DIGIT_DIM*DIM-1:0] weights [ROWS-1:0][COLS-1:0];
    reg signed [DIGIT_DIM-1:0] trainX [TRAIN_ROWS-1:0][DIM-1:0];    
    reg signed [DIGIT_DIM-1:0] testX [TEST_ROWS-1:0][DIM-1:0];
    reg [LOG2_NUM_CLASSES-1:0] trainY [TRAIN_ROWS-1:0];
    reg [LOG2_NUM_CLASSES-1:0] testY [TEST_ROWS-1:0];
    
    reg signed [LOG2_ROWS:0] i = 0;
    reg signed [LOG2_COLS:0] j = 0;
    reg signed [LOG2_DIM:0] k = DIM-1;
    reg signed [LOG2_DIM:0] kw = DIM-1;
    reg signed [LOG2_DIM:0] k1 = DIM-1;
    reg signed [LOG2_DIM:0] k2 = DIM-1;    
    
    reg signed [LOG2_TRAIN_ROWS:0] t1 = 0;
    reg signed [LOG2_TEST_ROWS:0] t2 = 0;
    
    integer weights_file;
    integer trains_file;
    integer test_file;
    
    reg [(DIM*DIGIT_DIM)-1:0] rand_v;
    reg [(DIM*DIGIT_DIM)+LOG2_NUM_CLASSES-1:0] temp_train_v;
    reg [(DIM*DIGIT_DIM)+LOG2_NUM_CLASSES-1:0] temp_test_v;
    
    integer eof_weight;
    integer eof_train;
    integer eof_test;
    
    ///////////////////////////////////////////////////////*******************Read weight vectors***********/////////////////////////////////////
    initial begin
        $readmemb("isom_train_x.mem", trainX);
    end
    
    initial begin
        $readmemb("isom_train_y.mem", trainY);
    end
    
    initial begin
        $readmemb("isom_test_x.mem", testX);
    end
    
    initial begin
        $readmemb("isom_test_y.mem", testY);
    end
    
    initial begin
        $readmemb("isom_weights.mem", weights);
    end
    
    ////////////////////*****************************Initialize frequenct list*************//////////////////////////////
    always @(posedge clk) begin
        if (variable_init_en) begin        
            for (ii = 0; ii < ROWS; ii = ii + 1) begin
                for (jj = 0; jj < COLS; jj = jj + 1) begin
                    for (kk = 0; kk < NUM_CLASSES; kk = kk + 1) begin
                        class_frequency_list[ii][jj][kk] = 0;
                    end
                end
            end
//        $display("class frequnecy list initialized");
        variable_init_en=0;
        end
    end
    
    ///////////////////////////////////////////////////////****************Start LFSR**************/////////////////////////////////////
    
    reg lfsr_en = 1;
    reg seed_en = 1;
    wire [(DIM*RAND_NUM_BIT_LEN)-1:0] random_number_arr;
    
    genvar dim_i;
    
    generate
        for(dim_i=1; dim_i <= DIM; dim_i=dim_i+1) begin
            lfsr #(.NUM_BITS(RAND_NUM_BIT_LEN)) lfsr_rand
            (
                .i_Clk(clk),
                .i_Enable(lfsr_en),
                .i_Seed_DV(seed_en),
                .i_Seed_Data(dim_i[RAND_NUM_BIT_LEN-1:0]),
                .o_LFSR_Data(random_number_arr[(dim_i*RAND_NUM_BIT_LEN)-1 : (dim_i-1)*RAND_NUM_BIT_LEN])
            );
        end
    endgenerate
    
    ///////////////////////////////////////////////////////*******************Start Training***********/////////////////////////////////////
    always @(posedge clk) begin
        if (training_en) begin
//            $display("training_en");
            iteration = -1;
            next_iteration_en = 1;
            training_en = 0;
        end
    end
    
    always @(posedge clk) begin
        if (next_iteration_en) begin
            t1 = -1; // reset trainset pointer
            if (iteration<(TOTAL_ITERATIONS-1)) begin
                iteration = iteration + 1;
                next_x_en = 1;                
            end
            else begin
                iteration = -1;                
                next_x_en = 0;
                init_classification_en = 1; // start classification
            end
            
            next_iteration_en = 0;            
        end
    end
    
    always @(posedge clk)
    begin
        if (next_x_en && !classification_en) begin                
            if (t1<TRAIN_ROWS-1) begin        
                t1 = t1 + 1;
                dist_enable = 1;
            end            
            else begin
//                $display("next_iteration_en ", iteration); 
                next_iteration_en = 1;  
            end
                               
            next_x_en = 0;
        end
    end
    
    /////////////////////////////////////******************************Classification logic******************************/////////////////////////////////
    always @(posedge clk)
    begin
        if (init_classification_en)
        begin
//            $display("init_classification_en"); 
            lfsr_en = 0; // turn off the random number generator
            next_x_en = 1;
            classification_en = 1;
            init_classification_en = 0;
        end
    end
    
    always @(posedge clk)
    begin
        if (next_x_en && classification_en)
        begin       
            // classify prev x 's bmu
            if (t1>=0)
                class_frequency_list[bmu[1]][bmu[0]][trainY[t1]] =  class_frequency_list[bmu[1]][bmu[0]][trainY[t1]] + 1;
                      
            if (t1<TRAIN_ROWS-1)
            begin                           
                t1 = t1 + 1;
                dist_enable = 1;
//                $display("classify ", t1);    
            end            
            else
            begin    
//                $display("classification_en STOPPED"); 
                classification_en = 0;          
                class_label_en = 1;                
            end 
                         
            next_x_en = 0;
        end
    end
    
    //////////////////******************************Find BMU******************************/////////////////////////////////
    reg [LOG2_DIM-1:0] iii = 0; 
    
    reg [LOG2_DIM:0] hamming_distance;
    reg [LOG2_DIM:0] min_distance = DIM;  
    
    reg [LOG2_DIM:0] dot_product;
    reg [LOG2_DIM:0] w_l2_norm;
     
    reg [LOG2_DIM:0] distances [ROWS-1:0][COLS-1:0];       
    reg [LOG2_COLS:0] minimum_distance_indices [(ROWS*COLS-1):0][1:0];
    reg [LOG2_DIM-1:0] min_distance_next_index = 0;
    
    reg [LOG2_DIM:0] non_zero_count;    
    reg [LOG2_DIM:0] max_l0_norm;
    reg [LOG2_DIM:0] l0_norms [ROWS-1:0][COLS-1:0]; 
        
    reg [LOG2_ROWS:0] idx_i;
    reg [LOG2_COLS:0] idx_j;        
    
    always @(posedge clk)
    begin
        if (dist_enable)
        begin
            i = 0;
            j = 0;
            k = 0;
            min_distance_next_index = 0; // reset index
            min_distance = DIM;
            
            dot_product = 0;
            w_l2_norm = 0;
            
            for (i=0;i<ROWS;i=i+1)
            begin
                for (j=0;j<COLS;j=j+1)
                begin
                    hamming_distance = 0;
                    non_zero_count = 0;
                    for (k=0;k<DIM;k=k+1)
                    begin
                        // get distnace
                        hamming_distance = hamming_distance + (weights[i][j][(k+1)*DIGIT_DIM-1 -:DIGIT_DIM]*trainX[t1][k] == 2'b11 ? 2'b01 : 2'b00);
                        // get zero count
                        non_zero_count = non_zero_count + (weights[i][j][(k+1)*DIGIT_DIM-1 -:DIGIT_DIM] == 2'b00 ? 2'b00 : 2'b01); 
                        
                        dot_product = dot_product + weights[i][j][(k+1)*DIGIT_DIM-1 -:DIGIT_DIM]*trainX[t1][k];
                        
                    end // k

                    distances[i][j] = DIM - dot_product;
                    l0_norms[i][j] = non_zero_count;
                    
                    // get minimum distance index list
                    if (min_distance == hamming_distance) begin
                        minimum_distance_indices[min_distance_next_index][1] = i;
                        minimum_distance_indices[min_distance_next_index][0] = j;
                        min_distance_next_index = min_distance_next_index + 1;
                    end
                    
                    if (min_distance>hamming_distance) begin
                        min_distance = hamming_distance;
                        minimum_distance_indices[0][1] = i;
                        minimum_distance_indices[0][0] = j;                        
                        min_distance_next_index = 1;
                    end
                end //j                
            end // i
            
            // more than one bmu
            if (min_distance_next_index > 1) begin  // more than one bmu
                iii = 0;
                max_l0_norm = 0;
                for(iii=0;iii<(ROWS*COLS-1); iii=iii+1) begin
                    if (iii<min_distance_next_index) begin
                        idx_i = minimum_distance_indices[iii][1];
                        idx_j = minimum_distance_indices[iii][0];
                        
                        if (l0_norms[idx_i][idx_j] >= max_l0_norm) begin
                            max_l0_norm = l0_norms[idx_i][idx_j];
                            bmu[1] = idx_i;
                            bmu[0] = idx_j;
                        end
                    end
                end
            end            
            else begin // only one minimum distance node is there 
                bmu[1] = minimum_distance_indices[0][1];
                bmu[0] = minimum_distance_indices[0][0];
            end            
            
            if (!classification_en)
                init_neigh_search_en = 1; // find neighbours
            else
                next_x_en = 1; // classify node
                
            dist_enable = 0;
        end        
    end
    
    //////////////////////************Start Neighbourhood search************//////////////////////////////////////////
    
    reg signed [LOG2_ROWS+1:0] bmu_i;
    reg signed [LOG2_COLS+1:0] bmu_j;
    reg signed [LOG2_ROWS+1:0] bmu_x;
    reg signed [LOG2_COLS+1:0] bmu_y;
    reg signed [LOG2_NB_RADIUS+1:0] man_dist; /////////// not sure
    reg signed [LOG2_NB_RADIUS+1:0] nb_radius = INITIAL_NB_RADIUS;
    reg signed [LOG2_UPDATE_PROB+1:0] update_prob = INITIAL_UPDATE_PROB;
    integer signed step_i;
     
    // update update probability
    always @(posedge clk)
    begin
        for (step_i=1; step_i<=STEP;step_i = step_i+1)
        begin
            if ((iteration<(ITERATION_STEP*step_i)) && (iteration>=(ITERATION_STEP*(step_i-1))))
            begin
                update_prob <= UPDATE_PROB_STEP*(STEP-step_i+1);
            end
        end
    end
    
    // update neighbourhood radius
    always @(posedge clk)
    begin
        for (step_i=1; step_i<=4;step_i = step_i+1)
        begin
            if ( (iteration<(ITERATION_NB_STEP*step_i)) && (iteration>= (ITERATION_NB_STEP*(step_i-1)) ) ) begin
                nb_radius <=  NB_RADIUS_STEP*(4-step_i);
            end
        end
    end
    
    always @(posedge clk)
    begin    
        if (init_neigh_search_en) begin
            bmu_x = bmu[1]; bmu_y = bmu[0];  
            bmu_i = (bmu_x-nb_radius) < 0 ? 0 : (bmu_x-nb_radius);            
            bmu_j = (bmu_y-nb_radius) < 0 ? 0 : (bmu_y-nb_radius);
            init_neigh_search_en=0;
            nb_search_en=1;
        end
    end
    
    reg signed [DIGIT_DIM:0] temp;
    reg signed [DIGIT_DIM-1:0] signed_weight;
    integer digit;

    always @(posedge clk)
    begin    
        if (nb_search_en) begin  
            man_dist = (bmu_x-bmu_i) >= 0 ? (bmu_x-bmu_i) : (bmu_i-bmu_x);
            man_dist = man_dist + ((bmu_y - bmu_j)>= 0 ? (bmu_y - bmu_j) : (bmu_j - bmu_y));              
            
            if (man_dist <= nb_radius) begin
                // update neighbourhood
                for (digit=0; digit<DIM; digit=digit+1) begin
                   if (random_number_arr[RAND_NUM_BIT_LEN*digit +: RAND_NUM_BIT_LEN] < update_prob) begin                        
                        seed_en = 0;
                        signed_weight = weights[bmu_i][bmu_j][(digit+1)*DIGIT_DIM-1 -:DIGIT_DIM];
                                              
                        temp = signed_weight + trainX[t1][digit];
                        
                        if (temp > k_value) 
                            weights[bmu_i][bmu_j][(digit+1)*DIGIT_DIM-1 -:DIGIT_DIM] = k_value;
                        else if (temp < -k_value) 
                            weights[bmu_i][bmu_j][(digit+1)*DIGIT_DIM-1 -:DIGIT_DIM] = -k_value;
                        else 
                            weights[bmu_i][bmu_j][(digit+1)*DIGIT_DIM-1 -:DIGIT_DIM] = temp;
                    end
                end                
            end
                        
            bmu_j = bmu_j + 1;
                                    
            if (bmu_j == bmu_y+nb_radius+1 || bmu_j == COLS) begin
                bmu_j = (bmu_y-nb_radius) < 0 ? 0 : (bmu_y-nb_radius);                
                bmu_i = bmu_i + 1;
            end            
            if (bmu_i == bmu_x+nb_radius+1 || bmu_i==ROWS) begin
                nb_search_en = 0; // neighbourhood search finished        
                next_x_en = 1; // go to the next input
            end            
        end
    end
    
    /////////////////////************Start Classification of weight vectors********///////////////////////
    reg [LOG2_NUM_CLASSES:0] class_labels [ROWS-1:0][COLS-1:0];    

    integer most_freq = 0;
    reg [3:0] default_freq [NUM_CLASSES-1:0];
    
    always @(posedge clk)
    begin
        if (class_label_en)
        begin
            $display("class_label_en");   
            i=0;j=0;k=0;
            for(i=0;i<ROWS;i=i+1)
            begin
                for(j=0;j<COLS;j=j+1)
                begin
                    most_freq = 0;
                    class_labels[i][j] = NUM_CLASSES-1; /////////// hardcoded default value
                    for(k=0;k<NUM_CLASSES-1;k=k+1)
                    begin
                        if (class_frequency_list[i][j][k]>most_freq)
                        begin
                            class_labels[i][j] = k;
                            most_freq = class_frequency_list[i][j][k];
                        end
                    end
                    if (class_labels[i][j] == NUM_CLASSES-1) /////////// hardcoded default value
                    begin                        
                        // reset array
                        for(k=0;k<=NUM_CLASSES-1;k=k+1)
                        begin
                            default_freq[k] = 0;
                        end
                        
                        if (i-1>0)
                        begin
                            k = class_labels[i-1][j];
                            default_freq[k] = default_freq[k] +1;
                        end
                        
                        if (i+1<ROWS)
                        begin
                            k = class_labels[i+1][j];
                            default_freq[k] = default_freq[k] +1;
                        end
                        
                        if (j-1>0)
                        begin
                            k = class_labels[i][j-1];
                            default_freq[k] = default_freq[k] +1;
                        end
                        
                        if (j+1<COLS)
                        begin
                            k = class_labels[i][j+1];
                            default_freq[k] = default_freq[k] +1;
                        end
                        
                        most_freq = 0;
                        for(k=0;k<=NUM_CLASSES-2;k=k+1) // only check 0,1,2
                        begin
                            if (default_freq[k] >= most_freq)
                            begin
                                most_freq = default_freq[k];
                                class_labels[i][j] = k;
                            end
                        end                      
                    end
                end
            end
            class_label_en = 0;
            test_en = 1;
            t2 = -1;
        end
    end
    
    //////////////////////////////***************Start test************************///////////////////////////////////////////////////////
    
    always @(posedge clk)
    begin
        if (test_en)
        begin
            if (t2<TEST_ROWS-1)
            begin
                t2 = t2 + 1;                
                classify_x_en = 1;
            end            
            else
            begin 
                test_en = 0;
                is_completed = 1;            
            end
        end
    end
    
    reg [LOG2_TEST_ROWS:0] correct_predictions = 0; // should take log2 of test rows
    reg [LOG2_NUM_CLASSES:0] predictionY[TEST_ROWS-1:0];
    
    reg [LOG2_TEST_ROWS:0] tot_predictions = 0;
    
    always @(posedge clk)
    begin
        if (classify_x_en)
        begin
            i = 0;
            j = 0;
            k = 0;
            min_distance_next_index = 0; // reset index
            min_distance = DIM;
            
            dot_product = 0;
            for (i=0;i<ROWS;i=i+1)
            begin
                for (j=0;j<COLS;j=j+1)
                begin
                    hamming_distance = 0;
                    non_zero_count = 0;
                    for (k=0;k<DIM;k=k+1)
                    begin
                        // get distnace
                        hamming_distance = hamming_distance + (weights[i][j][(k+1)*DIGIT_DIM-1 -:DIGIT_DIM]*testX[t2][k] == 2'b11 ? 2'b01 : 2'b00);
                        // get zero count
                        non_zero_count = non_zero_count + (weights[i][j][(k+1)*DIGIT_DIM-1 -:DIGIT_DIM] == 2'b00 ? 2'b00 : 2'b01); 
                        
                        dot_product = dot_product + weights[i][j][(k+1)*DIGIT_DIM-1 -:DIGIT_DIM]*trainX[t1][k];
                    end // k
                    
                    distances[i][j] = DIM - dot_product;
                    l0_norms[i][j] = non_zero_count;
                    
                    // get minimum distance index list
                    if (min_distance == hamming_distance)
                    begin
                        minimum_distance_indices[min_distance_next_index][1] = i;
                        minimum_distance_indices[min_distance_next_index][0] = j;
                        min_distance_next_index = min_distance_next_index + 1;
                    end
                    
                    if (min_distance>hamming_distance)
                    begin
                        min_distance = hamming_distance;
                        minimum_distance_indices[0][1] = i;
                        minimum_distance_indices[0][0] = j;                        
                        min_distance_next_index = 1;
                    end
                end //j                
            end // i
            
            if (min_distance_next_index > 1) begin  // more than one bmu
                iii = 0;
                max_l0_norm = 0;
                for(iii=0;iii<(ROWS*COLS-1); iii=iii+1) begin
                    if (iii<min_distance_next_index) begin
                        idx_i = minimum_distance_indices[iii][1];
                        idx_j = minimum_distance_indices[iii][0];
                        
                        if (l0_norms[idx_i][idx_j] >= max_l0_norm) begin
                            max_l0_norm = l0_norms[idx_i][idx_j];
                            bmu[1] = idx_i;
                            bmu[0] = idx_j;
                        end
                    end
                end
             end
            
            else begin
                bmu[1] = minimum_distance_indices[0][1];
                bmu[0] = minimum_distance_indices[0][0];
            end
            
            next_prediction_en=1;
            classify_x_en = 0;            
        end        
    end
    
    always @(posedge clk) begin
        if (next_prediction_en) begin
            if (class_labels[bmu[1]][bmu[0]] == testY[t2]) begin
                correct_predictions = correct_predictions + 1;                
            end    
            tot_predictions = tot_predictions +1;        
            predictionY[t2] = class_labels[bmu[1]][bmu[0]];  
               
            test_en = 1;
            next_prediction_en=0;
        end        
    end
    
//    integer fd;    
//    always @(posedge clk) begin
//        if (write_en) begin
//            fd = $fopen("/home/mad/Documents/Projects/fpga-isom/isom/weight_out.data", "w");
//            i=0; j=0; k=0;
//            for (i=0; i<=ROWS-1; i=i+1) begin
//                for (j=0; j<=COLS-1; j=j+1) begin
//                    for (k=DIM-1; k>=0; k=k-1) begin                        
//                        $fwriteb(fd, weights[i][j][(k+1)*DIGIT_DIM-1 -:DIGIT_DIM]);
//                    end
//                    $fwrite(fd, "\n");
//                end
//            end
            
//            #10 $fclose(fd);            
//            is_completed = 1;   
//        end
//    end
        
    assign prediction = correct_predictions;
    assign completed = is_completed;

endmodule
