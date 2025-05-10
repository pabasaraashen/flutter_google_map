import 'package:flutter/material.dart';
import 'package:google_place/google_place.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TransSearchBar extends StatefulWidget {
  final TextEditingController searchController;
  final Function(LatLng) onLocationSelected;
  final GooglePlace googlePlace;

  const TransSearchBar({
    Key? key,
    required this.searchController,
    required this.onLocationSelected,
    required this.googlePlace,
  }) : super(key: key);

  @override
  State<TransSearchBar> createState() => _TransSearchBarState();
}

class _TransSearchBarState extends State<TransSearchBar> {
  List<AutocompletePrediction> predictions = [];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          elevation: 5,
          borderRadius: BorderRadius.circular(10),
          child: TextField(
            controller: widget.searchController,
            decoration: InputDecoration(
              hintText: "Search location",
              prefixIcon: const Icon(Icons.search),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
            ),
            onChanged: (value) {
              if (value.isNotEmpty) {
                autoCompleteSearch(value);
              } else {
                setState(() {
                  predictions = [];
                });
              }
            },
          ),
        ),

        // Prediction list
        if (predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: predictions.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: const Icon(Icons.location_on, color: Colors.red),
                  title: Text(predictions[index].description ?? ""),
                  onTap: () async {
                    final placeId = predictions[index].placeId!;
                    final details = await widget.googlePlace.details.get(placeId);
                    if (details != null && details.result != null && details.result!.geometry != null) {
                      final location = details.result!.geometry!.location!;
                      LatLng newPos = LatLng(location.lat!, location.lng!);

                      setState(() {
                        predictions = [];
                        widget.searchController.clear();
                      });

                      // Call the callback function with the selected location
                      widget.onLocationSelected(newPos);
                    }
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  void autoCompleteSearch(String value) async {
    var result = await widget.googlePlace.autocomplete.get(value);
    if (result != null && result.predictions != null && mounted) {
      setState(() {
        predictions = result.predictions!;
      });
    }
  }
}