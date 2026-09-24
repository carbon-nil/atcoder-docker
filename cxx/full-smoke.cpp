// full のイメージのビルド時に ojt で動かし、外部ライブラリを AtCoder と同じフラグでビルド・実行できるかを確かめる
#include <bits/stdc++.h>
#include <absl/container/flat_hash_map.h>
#include <boost/multiprecision/cpp_int.hpp>
#include <gmpxx.h>
#include <LightGBM/c_api.h>
#include <ortools/linear_solver/linear_solver.h>
#include <torch/torch.h>
#include <z3++.h>

int main() {
    absl::flat_hash_map<int, int> m;
    m[1] = 2;

    boost::multiprecision::cpp_int b = 1;
    b <<= 70;

    mpz_class g = 3;
    g *= 5;

    std::unique_ptr<operations_research::MPSolver> s(operations_research::MPSolver::CreateSolver("SCIP"));
    auto* x = s->MakeIntVar(0, 10, "x");
    s->MutableObjective()->SetCoefficient(x, 1);
    s->MutableObjective()->SetMaximization();
    s->Solve();

    z3::context c;
    z3::solver z(c);
    auto a = c.int_const("a");
    z.add(a * 3 == 12);
    z.check();

    int omp = 0;
#pragma omp parallel for reduction(+ : omp)
    for (int i = 0; i < 4; i++) omp += 1;

    std::cout << m[1] << ' ' << b << ' ' << g.get_str() << ' ' << x->solution_value() << ' ' << z.get_model().eval(a) << ' '
              << torch::ones({2}).sum().item<float>() << ' ' << (LGBM_GetLastError() != nullptr) << ' ' << omp << '\n';
}
