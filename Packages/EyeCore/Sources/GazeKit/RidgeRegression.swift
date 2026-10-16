import Foundation

/// Ridge regression with an unpenalized bias, solved through the normal equations and a Cholesky factorization.
///
/// The problems here are small (a few hundred rows, a few dozen columns), so a direct solver is exact and fast.
enum RidgeRegression {
    /// The sums `XᵀX` and `Xᵀy` (for two targets) of a set of rows; sets combine by addition and subtraction,
    /// which makes leave-one-group-out cross-validation cheap.
    struct NormalEquations: Equatable, Sendable {
        /// The number of columns.
        let width: Int

        /// `XᵀX`, row-major, upper triangle filled.
        var gram: [Double]

        /// `Xᵀy` for the first target.
        var firstMoment: [Double]

        /// `Xᵀy` for the second target.
        var secondMoment: [Double]

        /// The number of rows.
        var count: Int

        /// Empty sums.
        ///
        /// - Parameter width: The number of columns.
        init(width: Int) {
            self.width = width
            gram = [Double](repeating: 0, count: width * width)
            firstMoment = [Double](repeating: 0, count: width)
            secondMoment = [Double](repeating: 0, count: width)
            count = 0
        }

        /// Adds a row with its two targets.
        ///
        /// - Parameters:
        ///   - row: The design row.
        ///   - first: The first target.
        ///   - second: The second target.
        mutating func add(_ row: [Double], _ first: Double, _ second: Double) {
            for i in 0..<width {
                let value = row[i]
                firstMoment[i] += value * first
                secondMoment[i] += value * second
                for j in i..<width {
                    gram[i * width + j] += value * row[j]
                }
            }
            count += 1
        }

        static func + (lhs: NormalEquations, rhs: NormalEquations) -> NormalEquations {
            var sum = lhs
            for index in sum.gram.indices {
                sum.gram[index] += rhs.gram[index]
            }
            for index in 0..<sum.width {
                sum.firstMoment[index] += rhs.firstMoment[index]
                sum.secondMoment[index] += rhs.secondMoment[index]
            }
            sum.count += rhs.count
            return sum
        }

        /// Solves for the weights of both targets.
        ///
        /// - Parameter lambda: The penalty on every weight except the bias (column 0).
        /// - Returns: The weights of the first and the second target, or `nil` if the system is singular.
        func solve(lambda: Double) -> (first: [Double], second: [Double])? {
            guard count > 0 else {
                return nil
            }
            var matrix = gram
            for i in 0..<width {
                for j in 0..<i {
                    matrix[i * width + j] = matrix[j * width + i]
                }
                if i > 0 {
                    matrix[i * width + i] += lambda
                }
            }
            guard let first = solveSymmetricPositiveDefinite(matrix, firstMoment, size: width),
                let second = solveSymmetricPositiveDefinite(matrix, secondMoment, size: width)
            else {
                return nil
            }
            return (first, second)
        }
    }

    /// Fits weights for rows whose first value is the bias term 1.
    ///
    /// - Parameters:
    ///   - rows: The design rows, each starting with 1.
    ///   - targets: One target per row.
    ///   - lambda: The penalty on every weight except the bias.
    /// - Returns: The weights, or `nil` if the system is singular.
    static func fit(rows: [[Double]], targets: [Double], lambda: Double) -> [Double]? {
        guard let width = rows.first?.count, rows.count == targets.count, width > 0 else {
            return nil
        }
        var equations = NormalEquations(width: width)
        for (row, target) in zip(rows, targets) {
            equations.add(row, target, 0)
        }
        return equations.solve(lambda: lambda)?.first
    }

    /// Applies weights to a design row.
    ///
    /// - Parameters:
    ///   - weights: The weights.
    ///   - row: The design row, starting with 1.
    /// - Returns: The prediction.
    static func predict(_ weights: [Double], _ row: [Double]) -> Double {
        zip(weights, row).reduce(0) { $0 + $1.0 * $1.1 }
    }

    /// Solves `A x = b` for a symmetric positive definite matrix stored row-major.
    ///
    /// - Parameters:
    ///   - matrix: The matrix, `size * size` values.
    ///   - vector: The right-hand side.
    ///   - size: The dimension.
    /// - Returns: The solution, or `nil` if the matrix is not positive definite.
    static func solveSymmetricPositiveDefinite(_ matrix: [Double], _ vector: [Double], size: Int) -> [Double]? {
        var lower = [Double](repeating: 0, count: size * size)
        for i in 0..<size {
            for j in 0...i {
                var sum = matrix[i * size + j]
                for k in 0..<j {
                    sum -= lower[i * size + k] * lower[j * size + k]
                }
                if i == j {
                    guard sum > 1e-12 else {
                        return nil
                    }
                    lower[i * size + i] = sum.squareRoot()
                } else {
                    lower[i * size + j] = sum / lower[j * size + j]
                }
            }
        }
        var forward = [Double](repeating: 0, count: size)
        for i in 0..<size {
            var sum = vector[i]
            for k in 0..<i {
                sum -= lower[i * size + k] * forward[k]
            }
            forward[i] = sum / lower[i * size + i]
        }
        var solution = [Double](repeating: 0, count: size)
        for i in stride(from: size - 1, through: 0, by: -1) {
            var sum = forward[i]
            for k in (i + 1)..<size {
                sum -= lower[k * size + i] * solution[k]
            }
            solution[i] = sum / lower[i * size + i]
        }
        return solution
    }
}
