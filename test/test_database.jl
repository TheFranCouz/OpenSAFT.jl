using OpenSAFT, Test

@testset "database_lookup" begin
    # Quick test to show that lookups in the OpenSAFT database works.
    @test haskey(OpenSAFT.getparams(["water", "methanol"], ["SAFT/PCSAFT"]), "sigma")

    # The rest of the test will be conducted with a custom dataset in the test_csvs directory.
    testspecies = ["sp1", "sp2", "sp3", "sp4", "sp5"]

    filepath_normal = ["test_csvs/normal_pair_test.csv",
                       "test_csvs/normal_single_test.csv",
                       "test_csvs/normal_assoc_test.csv",
                       "test_csvs/normal_single2_test.csv",
                       "test_csvs/normal_assoc2_test.csv"]

    filepath_clashingheaders = ["test_csvs/headercollision_single_test",
                                "test_csvs/headercollision_assoc_test"]

    filepath_asymmetry = ["test_csvs/asymmetry_pair_test",
                          "test_csvs/asymmetry_assoc_test"]

    # Check that it detects the right sites.
    @test OpenSAFT.findsitesincsvs(testspecies, filepath_normal) == [[],
                                                                     [],
                                                                     ["e", "e2", "H"],
                                                                     ["e", "H"],
                                                                     ["e", "e2", "H"]]

    # Check that it throws an error if ignore_missingsingleparams is not set to true.
    @test_throws ErrorException OpenSAFT.getparams(testspecies; userlocations=filepath_normal)

    params = OpenSAFT.getparams(testspecies; userlocations=filepath_normal, ignore_missingsingleparams=true)

    # Check that all the types are correct.
    @test typeof(params["intparam"]) <: OpenSAFT.SingleParam{Int}
    @test typeof(params["doubleparam"]) <: OpenSAFT.SingleParam{Float64}
    @test typeof(params["boolparam"]) <: OpenSAFT.SingleParam{Bool}
    @test typeof(params["stringparam"]) <: OpenSAFT.SingleParam{String}
    # If column has both strings and numbers, they should all be strings.
    @test typeof(params["mixedparam"]) <: OpenSAFT.SingleParam{String}
    # Contains missing values
    @test typeof(params["missingparam"]) <: OpenSAFT.SingleParam{Int}
    # All missing values
    @test typeof(params["emptyparam"]) <: OpenSAFT.SingleParam{Any}
    # Overwrite Int with Float, and also an upgrade from single to pair param
    @test typeof(params["overwriteparam"]) <: OpenSAFT.PairParam{Float64}
    # Overwrite String with Int
    @test typeof(params["overwritestringparam"]) <: OpenSAFT.SingleParam{String}
    # Overwrite Int with String
    @test typeof(params["overwriteassocparam"]) <: OpenSAFT.AssocParam{String}

    # Check that values of "sp1" and "sp3" has been correctly overwritten.
    # "sp1" was overwritten from the same file
    # "sp3" was overwritten from a separate file, "normal_single2_test.csv"
    @test params["intparam"].values == [6, 2, 7, 4, 5]
    # Also check that "testsource1" and "testsource3" are not present, and in their place
    # we have "testsource6" and "testsource19".
    @test "testsource1" ∉ params["intparam"].sources
    @test "testsource3" ∉ params["intparam"].sources
    @test "testsource5" ∈ params["intparam"].sources
    @test "testsource19" ∈ params["intparam"].sources

    # Check that missing values have been correctly defaulted.
    @test params["missingparam"].values == [0, 2, 3, 0, 0]
    @test params["missingparam"].ismissingvalues == Bool[1, 0, 0, 1, 1]

    # Check that the promotion form 1D to 2D array is succesful, with non-diagonal values present and symmetrical.
    @test params["overwriteparam"].values == [1.6  4.0  0.0  0.0  0.0
                                              4.0  1.2  0.0  3.0  0.0
                                              0.0  0.0  1.3  2.0  0.0
                                              0.0  3.0  2.0  1.4  0.0
                                              0.0  0.0  0.0  0.0  1.5]
                                              
    @test params["overwriteparam"].diagvalues == [1.6, 1.2, 1.3, 1.4, 1.5]

    # Now check that assoc param is correct.
    @test params["assocparam"].values ==
    [[Array{Int64}(undef,0,0)]  [Array{Int64}(undef,0,0)]  [Array{Int64}(undef,0,3)          ]  [Array{Int64}(undef,0,2)]  [Array{Int64}(undef,0,3)       ]
     [Array{Int64}(undef,0,0)]  [Array{Int64}(undef,0,0)]  [Array{Int64}(undef,0,3)          ]  [Array{Int64}(undef,0,2)]  [Array{Int64}(undef,0,3)       ]
     [Array{Int64}(undef,3,0)]  [Array{Int64}(undef,3,0)]  [[0 0 2000; 0 0 2700; 2000 2700 0]]  [[0 0; 0 0; 2400 2300]  ]  [[0 0 0; 0 0 0; 0 0 0]         ]
     [Array{Int64}(undef,2,0)]  [Array{Int64}(undef,2,0)]  [[0 0 2400; 0 0 2300]             ]  [[0 0; 0 0]             ]  [[0 0 2600; 0 2500 0]          ]
     [Array{Int64}(undef,3,0)]  [Array{Int64}(undef,3,0)]  [[0 0 0; 0 0 0; 0 0 0]            ]  [[0 0; 0 2500; 2600 0]  ]  [[2200 0 2100; 0 0 0; 2100 0 0]]]


    # Clashing headers between association and non-association parameters are not allowed
    @test_throws ErrorException OpenSAFT.getparams(testspecies; userlocations=filepath_clashingheaders)

    # If parameter is not tagged as asymmetrical, having non-missing values across the diagonal will throw an error
    @test_throws ErrorException OpenSAFT.getparams(testspecies; userlocations=filepath_asymmetry, ignore_missingsingleparams=true)

    asymmetricparams = OpenSAFT.getparams(testspecies; userlocations=filepath_asymmetry, asymmetricparams=["asymmetricpair", "asymmetricassoc"], ignore_missingsingleparams=true)
    asymmetricparams["asymmetricpair"].values == [0.06  0.04  0.0  0.0   0.0
                                                  0.05  0.0   0.0  0.0   0.0
                                                  0.0   0.0   0.0  0.02  0.0
                                                  0.0   0.03  0.0  0.0   0.0
                                                  0.0   0.0   0.0  0.0   0.0]
    asymmetricparams["asymmetricassoc"].values ==
    [[Array{Int64}(undef,0,0)]  [Array{Int64}(undef,0,0)]  [Array{Int64}(undef,0,3)       ]  [Array{Int64}(undef,0,2) ]  [Array{Int64}(undef,0,3)    ]
     [Array{Int64}(undef,0,0)]  [Array{Int64}(undef,0,0)]  [Array{Int64}(undef,0,3)       ]  [Array{Int64}(undef,0,2) ]  [Array{Int64}(undef,0,3)    ]
     [Array{Int64}(undef,3,0)]  [Array{Int64}(undef,3,0)]  [[0 0 2800; 0 0 0; 2000 2700 0]]  [[0 2900; 0 0; 2400 2300]]  [[0 0 0; 0 0 0; 0 0 0]      ]
     [Array{Int64}(undef,2,0)]  [Array{Int64}(undef,2,0)]  [[0 0 0; 0 0 0]                ]  [[0 0; 0 0]              ]  [[0 0 0; 0 2500 0]          ]
     [Array{Int64}(undef,3,0)]  [Array{Int64}(undef,3,0)]  [[0 0 0; 0 0 0; 0 0 0]         ]  [[0 0; 0 0; 2600 0]      ]  [[2200 0 0; 0 0 0; 2100 0 0]]]

    # Also, since a non-missing value exists on the diagonal of "asymmetricpair",
    # and the diagonal contains missing values, it should throw an error
    # without ignore_missingsingleparams set to true.
    @test_throws ErrorException OpenSAFT.getparams(testspecies; userlocations=filepath_asymmetry, asymmetricparams=["asymmetricpair", "asymmetricassoc"])

    # todo: tests for GC
end
