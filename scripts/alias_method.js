/**
	 * Returns a random sampler for the discrete probability distribution
	 * defined by the given array
	 * @param inputProbabilities The array of input probabilities to use.
	 *   The array's values must be Numbers, but can be of any magnitude
	 * @returns A function with no arguments that, when called, returns
	 *   a number between 0 and inputProbabilities.length with respect to
	 *   the weights given by inputProbabilities.
	 */
 function alias_method(inputProbabilities) {
  var probabilities, aliases;
  
  // First copy and type-check the input probabilities,
  // also taking their sum.
  probabilities = inputProbabilities.map(function(p, i){
    if (Number.isNaN(Number(p))){
      throw new TypeError("Non-numerical value in distribution at index " + i);
    }
    return Number(p);		
  });
  var probsum = inputProbabilities.reduce(function(sum, p){
    return sum + p;
  }, 0);
  
  // Scale all of the probabilities such that their average is 1
  // (i.e. if all of the input probabilities are the same, then they 
  // are all set to 1 by this procedure)
  var probMultiplier = inputProbabilities.length / probsum;
  probabilities = probabilities.map(function(p, i) {
    return p * probMultiplier;
  });

  // Sort the probabilities into overFull and underFull queues
  var overFull = [], underFull = [];
  probabilities.forEach(function (p, i){
    if (p >= 1) overFull.push(i);
    else if (p < 1) underFull.push(i);
    else if (p !== 1) {
      throw new Error("User program has disrupted JavaScript defaults "
      + "and prevented this function from executing correctly.");
    }
  });

  // Construct the alias table.
  // In each iteration, the remaining space in an underfull cell
  // will be filled by surplus space from an overfull cell, such
  // that the underfull cell becomes exactly full.
  // The overfull cell will then be reclassified as to how much
  // probability it has left.
  aliases = [];
  while (overFull.length > 0 || underFull.length > 0) {
    if (overFull.length > 0 && underFull.length > 0){
      aliases[underFull[0]] = overFull[0];
      probabilities[overFull[0]] += probabilities[underFull[0]] - 1;
      underFull.shift();

      if (probabilities[overFull[0]] >= 1) overFull.push(overFull.shift());
      else if (probabilities[overFull[0]] < 1) underFull.push(overFull.shift());
      else overFull.shift();
    } else {
      // Because the average of all the probabilities is 1, mathematically speaking,
      // this block should never be reached. However, because of rounding errors
      // posed by floating-point numbers, a tiny bit of surplus can be left over.
      // The error is typically neglegible enough to ignore.
      var notEmptyArray = overFull.length > 0 ? overFull : underFull;
      notEmptyArray.forEach(function(index) {
        probabilities[index] = 1;
        aliases[index] = index;
      });
      notEmptyArray.length = 0;
    }
  }

  probabilities = probabilities.map(p => Math.floor(p * 100))
  return {probabilities, aliases}
}

function sample(probabilities, aliases, n) {
  const rarities = []
  for(let i = 0; i < n; i++)  {
    var seed = Math.floor(Math.random() * n);
    var index = seed % probabilities.length;
    rarities.push( seed * 100 / n < probabilities[index] ? index : aliases[index]);
  }
  return rarities
}

function test() {
  const {probabilities, aliases} = alias_method([60, 25, 10, 5])
  console.log(probabilities, aliases)

  const rarities = sample(probabilities, aliases, 100)
  console.log(rarities)

  console.log(
    rarities.filter(i => i == 0).length,
    rarities.filter(i => i == 1).length,
    rarities.filter(i => i == 2).length,
    rarities.filter(i => i == 3).length
  )
}

test()